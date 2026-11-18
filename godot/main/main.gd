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
const AccountDeletion = preload("res://net/account_deletion.gd")
const DeletionScreen = preload("res://ui/deletion_screen.gd")
const DeviceAccount = preload("res://net/device_account.gd")
const OnlineScreen = preload("res://ui/online_screen.gd")
const Recovery = preload("res://net/account_recovery.gd")
const RecoveryScreen = preload("res://ui/recovery_screen.gd")
const EmailScreen = preload("res://ui/email_screen.gd")
const Tutorial = preload("res://ui/tutorial.gd")
const Announcer = preload("res://fx/announcer.gd")
const Callout = preload("res://fx/comic_callout.gd")
var _code_taps: int = 0
var _code_owner: String = ""
var _code_pending: bool = false
var _code_message: String = "Unlock characters and backgrounds for your account. Codes never change match rules."
const Themes = preload("res://themes/registry.gd")
const Roster = preload("res://characters/roster.gd")
const Profile = preload("res://characters/profile.gd")
const HeroRig = preload("res://characters/art.gd")
const HeroSelect = preload("res://characters/select.gd")
const HeroVideo = preload("res://characters/hero_video.gd")
const Cinematic = preload("res://characters/cinematic.gd")
const Sound = preload("res://fx/sound.gd")
const Clock = preload("res://net/turn_clock.gd")
const Social = preload("res://net/social.gd")
const ChatPanel = preload("res://ui/chat_panel.gd")
## Round 5a: "<Name> joined" beat before the versus intro (protocol 2 only).
const JOINED_BEAT = 1.6
const Tournament = preload("res://tournament/flow.gd")
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
var tournament = Tournament.new()
var online_tournament = preload("res://tournament/online_flow.gd").new()
var account = DeviceAccount.new()
var deletion = AccountDeletion.new()
var online_api = JsonAPI.new()
## Explicit harness/capture opt-out; never derived from character-select onboarding.
var test_online_bypass: bool = false
var online_view
var recovery = Recovery.new()
var email_view
var _email_draft: String = ""
var _email_code_draft: String = ""
var _onboarding_email_confirmation: bool = false
var tutorial
var _tutorial_return_overlay: String = ""
var _tutorial_continue: Callable
var _tutorial_waiting: bool = false
var lobby_timer: Timer
var public_rooms: Array = []
var leaderboard_players: Array = []
var leaderboard_me: Dictionary = {}
var _lobby_pending: bool = false
var _onboarding_destination: String = "title"
var _onboarding_name: String = ""
var _onboarding_create: bool = false
var _room_password: String = ""
var _hero_changed: bool = false
var rival_character: String = "auric_rex"
var hero_select
var cinematic
var hero_video = HeroVideo.new()
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
var timer_overlay: Layer
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
## Round 5a: capability gate, moderation, chat and the turn clock display.
var social = Social.new()
## Tests and captures inject a fake HTTPRequest for live rooms (never the network).
var http_request_factory: Callable
var end_message: String = ""
var joined_timer: Timer
var chat_open: bool = false
var chat_unread: int = 0
var chat_muted: bool = false
var chat_blocked: bool = false
var chat_status: String = ""
var _chat_draft: String = ""
var chat_view
var prompt_layer: Control
var blocked_status: String = ""
var _prompt_key: String = ""
var _prompt_sent: String = ""
var _moved_turn: String = ""
var _you_name: String = ""

func _ready():
	# Handle close/Android back ourselves so first-run onboarding cannot dismiss.
	get_tree().auto_accept_quit = false; get_tree().quit_on_go_back = false
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop = Backdrop.new(); backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); add_child(backdrop)
	board = Board.new(); board.game = game; board.cell_pressed.connect(play_cell); add_child(board)
	# Screen flash and fireworks: additive, above the board, below every UI control.
	fx_overlay = Layer.new(); fx_overlay.name = "FxOverlay"; fx_overlay.painter = _draw_fx_overlay
	fx_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE; fx_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var add = CanvasItemMaterial.new(); add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD; fx_overlay.material = add
	add_child(fx_overlay)
	# Foreground HUD: parent _draw runs BEFORE child portraits. Keep countdown visible
	# above hero artwork, without intercepting input or drawing over modal/versus screens.
	timer_overlay = Layer.new(); timer_overlay.name = "TurnTimerHUD"; timer_overlay.painter = _draw_timer_hud
	timer_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE; timer_overlay.z_index = 20
	timer_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); add_child(timer_overlay)
	sound = Sound.new(); add_child(sound)
	callout = Callout.new(); callout.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); add_child(callout)
	add_child(hero_video)
	cinematic = Cinematic.new(); cinematic.video_source = hero_video; cinematic.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); add_child(cinematic)
	cinematic.video_overlay.audio_active.connect(sound.set_hero_video_audio)
	cinematic.video_overlay.prelude_active = sound.versus_prelude_playing
	cinematic.video_overlay.prelude_ended.connect(sound.stop_versus_prelude)
	cinematic.video_overlay.intro_revealed.connect(sound.play_versus_clash)
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
	tutorial = Tutorial.new(); add_child(tutorial); tutorial.finished.connect(_tutorial_finished)
	if not profile.data.onboarded: profile.data.display_name = str(settings.values.player_name)
	account.player_received.connect(_account_player)
	account.name_updated.connect(_account_name)
	account.rename_flow_changed.connect(_settings_name_status)
	account.onboarding_complete.connect(_account_completed)
	account.sync_finished.connect(_account_sync_finished)
	account.email_flow_changed.connect(_account_email_flow_changed)
	account.email_verified.connect(_account_email_verified)
	account.error.connect(_account_error); account.api.completed.connect(_code_completed); add_child(account)
	deletion.changed.connect(func():
		if overlay in ["delete_account","local_reset"]: _rebuild())
	deletion.store = account.store
	deletion.deleted.connect(_account_deleted); add_child(deletion)
	recovery.changed.connect(func():
		if page == "recovery": _rebuild())
	recovery.recovered.connect(_account_recovered); add_child(recovery)
	online_api.completed.connect(_online_response); add_child(online_api)
	social.store = account.store
	if http_request_factory.is_valid(): social.api.request_factory = http_request_factory
	social.capabilities_changed.connect(_capabilities_changed)
	social.blocks_changed.connect(func(_names): blocked_status = "" ; if overlay == "blocked": _rebuild())
	social.finished.connect(_social_finished)
	add_child(social)
	account.player_received.connect(social.merge_player)
	joined_timer = Timer.new(); joined_timer.one_shot = true; add_child(joined_timer); joined_timer.timeout.connect(_joined_beat_done)
	lobby_timer = Timer.new(); lobby_timer.wait_time = 2.5; add_child(lobby_timer); lobby_timer.timeout.connect(_refresh_lobby)
	if not test_online_bypass:
		if not account.store.complete():
			page = "onboarding"; _onboarding_name = account.store.data.screen_name
			if not _onboarding_name.is_empty(): _onboarding_create = true
		else:
			_account_name(account.store.data.screen_name)
			if not account.store.data.email_prompt_done:
				page = "email"; _email_draft = account.store.data.email
		# Adopt the old device-wide flag only for the identity already present.
		if account.store.complete() and settings.values.tutorial_completed:
			account.complete_tutorial()
		settings.set_value("tutorial_completed",false)
		account.refresh()
	tournament.setup(self)
	add_child(online_tournament); online_tournament.setup(self)
	_apply_preferences(); _relayout()
	if account.store.deletion_reset_required: _clear_local_account(account.store.deletion_reset_reason == "deleted", account.store.deletion_reset_reason == "signedout")
	if account.store.data.deletion_uncertain:
		page = "title"; overlay = "account_options"
	_rebuild()
	get_viewport().size_changed.connect(_on_viewport_resize)
	call_deferred("_clip_preview")
	call_deferred("_tutorial_on_home")
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
	if tutorial and tutorial.active: tutorial.relayout(layout)
	callout.region = Rect2(layout.board.position+Vector2(8,-8),Vector2(layout.board.size.x-16,52))
	_title = _title_geometry()
	backdrop.title_anchor = _title.anchor; backdrop.title_region = _title.region
	var fs: int = _title.font_size
	title_label.text = "LEXERLY"; title_label.add_theme_font_size_override("font_size",fs)
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
	backdrop.background_theme = str(settings.values.background_theme) if Themes.valid(str(settings.values.background_theme),Themes.available(settings.values.unlocked_backgrounds)) else "crystal"
	board.reduced_motion = bool(settings.values.reduced_motion)
	backdrop.reduced_motion = bool(settings.values.reduced_motion)
	sound.configure(settings.values)
	callout.reduced_motion = board.reduced_motion
	cinematic.reduced_motion = board.reduced_motion
	if tutorial: tutorial.reduced_motion = board.reduced_motion
	cinematic.video_overlay.set_sound_enabled(sound.enabled)
	if is_instance_valid(hero_select): hero_select.reduced_motion = board.reduced_motion
	for rig in field_heroes.values(): rig.reduced_motion = board.reduced_motion
func _process(delta):
	if _name_required() and (page not in ["onboarding","recovery"] or not overlay.is_empty()):
		_require_screen_name(); return
	if _resize_pending and not get_viewport().gui_get_focus_owner() is LineEdit:
		_resize_pending = false; _relayout(); _rebuild()
	clock += delta
	if cinematic: cinematic.advance(delta)
	_update_hero_states()
	P.clock = clock
	_input_beat = maxf(0,_input_beat-delta)
	if page == "game" and overlay.is_empty() and game.status == 0 and not _debug_capture and not (cinematic.active and cinematic.kind == "versus"): match_seconds += delta
	if page == "game" and thinking and overlay.is_empty() and not _debug_capture:
		thinking_age += delta
		ai.step(4500)
		if ai.done and thinking_age >= .38:
			thinking = false
			var m = ai.best_move
			if mode == "online" and demo_rival != null:
				demo_rival.send_move(m.x,m.y,online_sequence+1)
			elif mode == "computer": _apply_move(m.x,m.y)
	if page == "game" and hint_busy:
		hint_ai.step(3500)
		if hint_ai.done:
			hint_busy = false
			# Only show a hint computed for the position still on the board.
			if _hint_ply == game.history.size() and game.is_legal(hint_ai.best_move.x,hint_ai.best_move.y): board.hint_move = hint_ai.best_move
	if page == "game" and not tutorial.active and game.status != 0 and not board.win_fx.is_empty() and board.win_progress() >= RESULT_AT and not _result_shown:
		if not _spotlight_done:
			if not cinematic.active:
				board.frozen = true
				_show_spotlight()
		else:
			_result_shown = true; overlay = "result"; _rebuild()
	tick_online()
	_sync_fx()
	queue_redraw()
## Round 5a: re-evaluate the "Still there?" prompt as the local countdown crosses still_there_at.
func tick_online():
	if mode != "online" or page != "game" or not transport is HTTP: return
	if overlay.is_empty() and prompt_state() != _prompt_key: _clock_changed()
	if is_instance_valid(prompt_layer): prompt_layer.queue_redraw()
## Effects that depend on the board's animation clock: statue glow, result panel entrance.
func _sync_fx():
	_sync_turn_affordances()
	if board.win_fx.is_empty():
		backdrop.win_player = 0; backdrop.win_glow = 0; _result_t = 1.0
	else:
		var p = board.win_progress()
		backdrop.win_player = int(board.win_fx.player) if board.win_fx.player in [1,2] else 0
		backdrop.win_glow = clampf(p*3,0,1)*(.75+.25*sin(clock*4))
		_result_t = clampf((p-RESULT_AT)/.2,0,1)
	if overlay == "result": _apply_result_anim()
	if fx_overlay: fx_overlay.queue_redraw()
	if timer_overlay: timer_overlay.queue_redraw()
func _apply_result_anim():
	if cinematic.kind in ["spotlight","draw"]:
		var g = cinematic.result_geometry(layout.size)
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
	if _require_screen_name("online" if new_mode == "online" else "title"): return
	if new_mode == "online": request_online(); return
	if _tutorial_gate(func(): request_game(new_mode,mark)): return
	_pending_game = {"mode":new_mode,"mark":mark}
	_select_player = 1 if new_mode == "local" else 0; _local_picked = false
	open_character_select()
func open_character_select():
	if _require_screen_name(): return
	thinking = false; page = "character_select"; overlay = ""
	_hero_focus = str(profile.data.character_id); _name_draft = str(profile.data.display_name)
	_rebuild()
func _confirm_hero(id: String, display_name: String):
	if _require_screen_name(): return
	if not Roster.selectable(id,settings.values.unlocked_heroes): return
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
		if pending.mode == "tournament": tournament.create(id)
		elif pending.mode == "resume": resume_game()
		elif pending.mode == "online_lobby": open_online()
		else: start_game(pending.mode,pending.mark,false,true)
	else:
		sound.stinger(Roster.audio_index(id),"tag",-.35)
		cinematic.show_scene("lock_in",id,rival_character,human_mark,layout)
func _cinematic_finished(kind: String):
	if kind == "lock_in": go_home()
	elif kind == "versus":
		board.frozen = false; overlay = ""
		_rebuild(); _schedule_ai(); _announce("ready")
	elif kind in ["spotlight","draw"]:
		_spotlight_done = true; board.frozen = false
		_result_shown = true; overlay = "result"; _rebuild(); _sync_fx()
func _input(event):
	if overlay in ["delete_account","local_reset"]:
		if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
			_deletion_action("cancel"); get_viewport().set_input_as_handled()
		return
	# Recovery is a legitimate pre-account screen. Let its controls receive real
	# pointer/key events instead of routing every event back through registration.
	if page == "recovery":
		if event is InputEventKey and event.pressed and (event.keycode in [KEY_ESCAPE,KEY_BACK] or event.is_action_pressed("ui_cancel")):
			_recovery_action("cancel"); get_viewport().set_input_as_handled()
		return
	if _name_required():
		_require_screen_name()
		if event is InputEventKey and (event.keycode in [KEY_ESCAPE,KEY_BACK] or event.is_action_pressed("ui_cancel")):
			get_viewport().set_input_as_handled()
		return
	var pointer = event is InputEventScreenTouch or (event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT)
	# A touch that skipped a modal cinematic is followed by its emulated mouse press and the
	# release; swallow that one gesture so it cannot land on the newly shown Play Again/Menu.
	if pointer and Time.get_ticks_msec() < _skip_guard_until:
		if not event.pressed: _skip_guard_until = 0
		get_viewport().set_input_as_handled(); return
	var tap = (pointer and event.pressed) or (event is InputEventKey and event.pressed and not event.echo)
	if tap and overlay == "settings":
		var difficulty_control = controls.get("difficulty")
		if pointer and (not is_instance_valid(difficulty_control) or not difficulty_control.get_global_rect().has_point(event.position)): _code_taps = 0
	var result_skip = false
	if tap and cinematic and cinematic.combined_result:
		var g = cinematic.result_geometry(layout.size)
		result_skip = event is InputEventKey or (pointer and not g.again.has_point(event.position) and not g.menu.has_point(event.position))
	if tap and cinematic and cinematic.active and (not cinematic.buttons_shown or result_skip):
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
	cinematic.result_title = _victory_title()
	cinematic.result_detail = end_message if mode == "online" else ""
	cinematic.result_score = "%d — %d  BOARDS CLAIMED" % [game.owners.count(winner),game.owners.count(3-winner)]
	cinematic.show_scene("draw" if game.status == 3 else "spotlight",hero_for(winner),hero_for(3-winner),winner,layout)
	if game.status != 3 and not cinematic.video_playing(): sound.stinger(Roster.audio_index(hero_for(winner)),"full",-.35 if winner == human_mark else .35)
func _begin_versus():
	thinking = false; board.frozen = true
	cinematic.winner_name = side_name(human_mark); cinematic.loser_name = side_name(3-human_mark)
	cinematic.show_scene("versus",hero_for(human_mark),hero_for(3-human_mark),human_mark,layout)
	if cinematic.video_overlay._waiting_for_intros:
		var speech_length = sound.play_versus_prelude()
		cinematic.video_overlay.minimum_lead = maxf(cinematic.video_overlay.INTRO_LEAD_SECONDS,speech_length+.12 if speech_length > 0 else 0)
	if not cinematic.video_playing(): sound.cue("route"); sound.stinger(Roster.audio_index(hero_for(human_mark)),"tag",-.35)
func rematch():
	if online_tournament.match_active: online_tournament.return_to_bracket(); return
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
	start_game(mode,3-human_mark,true,true)
func _result_controls_refresh():
	if overlay == "result": _rebuild()

## `rematch` (Play Again) keeps the same rival hero; a new game from the menu/setup
## re-rolls. Round 3c product default, reversible: pass rematch=false to always re-roll.
func start_game(new_mode: String = "computer", mark: int = 1, rematch: bool = false, present: bool = false):
	if _require_screen_name(): return
	if not tournament.starting: tournament.match_active = false
	if new_mode == "online" and not test_online_bypass and not _debug_capture and not transport is Loopback and not account.store.online_ready(): open_online(); return
	_leave_online()
	cinematic.clear(); callout.callout = ""; _spotlight_done = false
	var keep = (rematch or (new_mode == "local" and _local_picked)) and Roster.valid(rival_character) and rival_character != str(profile.data.character_id)
	if not keep:
		var available: Array = []
		for h in Roster.DATA:
			if h.id != profile.data.character_id and not h.get("secret",false): available.append(h.id)
		rival_character = str(available[randi()%available.size()])
	hero_video.prefetch_pair(str(profile.data.character_id),rival_character)
	sound.prepare_character(Roster.audio_index(profile.data.character_id)); sound.prepare_character(Roster.audio_index(rival_character))
	mode = new_mode; human_mark = mark; page = "game"; overlay = ""; _debug_capture = false
	game.new_game(); board.game = game; board.clear_effects(); board.hint_move = Vector2i(-1,-1)
	thinking = false; hint_busy = false; _result_shown = false; match_seconds = 0; message = ""; online_sequence = 0
	_refresh_labels(); _rebuild()
	sound.clear_announcer()
	if present: _begin_versus()
	else: _schedule_ai(); _announce("ready")
func _schedule_ai():
	if page != "game":
		thinking = false; return
	if _debug_capture or game.status != 0 or not overlay.is_empty() or (cinematic.active and cinematic.kind == "versus"): return
	var should = mode == "computer" and game.turn != human_mark
	should = should or (mode == "online" and demo_rival != null and remote_ready and game.turn != human_mark)
	if should:
		thinking = true; thinking_age = 0
		ai.begin(game,tournament.match_level if tournament.match_active else str(settings.values.difficulty),ai_seed+game.history.size()*17)
func play_cell(b: int, c: int) -> bool:
	if _require_screen_name(): return false
	if cinematic.active and cinematic.kind == "versus": return false
	if page != "game" or not overlay.is_empty() or thinking or game.status != 0 or _input_beat > 0: return false
	if mode == "computer" and game.turn != human_mark: return false
	if mode == "online":
		if not local_online_turn():
			message = ""; return false
		if not game.is_legal(b,c): _invalid(b); return false
		# A move dismisses "Still there?" at once; the server ends the turn.
		_moved_turn = _turn_key(); transport.send_move(b,c,online_sequence+1); _clock_changed(); return true
	return _apply_move(b,c)
func _apply_move(b: int, c: int) -> bool:
	# Online polling stays authoritative while the instructional board is showing.
	if tutorial.active:
		if not game.play(b,c): return false
		_refresh_labels(); _save_match(); return true
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
	_sync_turn_affordances()
	board.sync_last_move(mode == "local",human_mark)
	turn_label = "Turn: "+("X" if game.turn == 1 else "O")
	active_label = "Active Board: "+("Any" if game.active_board == -1 else Rules.BOARD_NAMES[game.active_board])
	if game.status != 0:
		turn_label = "Draw" if game.status == 3 else ("X" if game.status == 1 else "O")+" wins"
		active_label = result_line()
func side_name(mark: int) -> String:
	if mark == human_mark and mode != "local": return _you_name if mode == "online" and not _you_name.is_empty() else str(settings.values.player_name)
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
	if mode == "online" and game.status == 0 and not local_online_turn():
		return [online_turn_caption(),"The board will glow when you can move."]
	if game.status != 0:
		var detail = "Nine boards woven. Play again?" if game.status == 3 else "Three boards in a row."
		return [result_line(),detail]
	var board_name = "Any" if game.active_board == -1 else Rules.BOARD_NAMES[game.active_board]
	var tail = "in any open board." if game.active_board == -1 else "in this 3×3 board."
	return ["Active Board: "+board_name,"Play your "+("X" if game.turn == 1 else "O")+" "+tail]
func undo_move() -> bool:
	# Round 3e: Undo exists only against the computer (spec item 1).
	if tournament.match_active and tournament.recorded: return false
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
	if tournament.match_active:
		tournament.capture_result(game.status); return
	if mode == "computer" and page == "game" and not _debug_capture:
		settings.saved_game = {"state":game.serialize(),"human":human_mark,"seconds":match_seconds,"character":profile.data.character_id,"rival_character":rival_character} if game.status == 0 else {}
		settings.save()
func resume_game():
	if _require_screen_name(): return
	tournament.match_active = false
	if settings.saved_game.is_empty(): return
	if not game.deserialize(settings.saved_game.state): settings.saved_game = {}; return
	mode = "computer"; _debug_capture = false; human_mark = int(settings.saved_game.human)
	var seconds = settings.saved_game.get("seconds",0)
	match_seconds = maxf(0,float(seconds)) if seconds is int or seconds is float else 0.0
	rival_character = str(settings.saved_game.get("rival_character","auric_rex"))
	# A hand-edited/legacy save may name an unknown hero or the player's own; pick a valid rival.
	if not Roster.valid(rival_character) or rival_character == str(profile.data.character_id):
		rival_character = "auric_rex" if profile.data.character_id != "auric_rex" else "vesper_vale"
	hero_video.prefetch_pair(str(profile.data.character_id),rival_character)
	page = "game"; overlay = ""; board.clear_effects(); _result_shown = false; _spotlight_done = false; cinematic.clear()
	_refresh_labels(); _rebuild()
	_schedule_ai()
func go_home():
	if _require_screen_name(): return
	if tutorial.active: tutorial.skip()
	_pending_game = {}; _select_player = 0
	sound.clear_announcer()
	_save_match(); tournament.match_active = false
	if online_tournament.match_active:
		online_tournament.match_active = false; online_tournament._auto_return = -1
	_leave_online(); thinking = false; page = "title"; overlay = ""; board.clear_effects(); cinematic.clear(); callout.callout = ""; _rebuild()
	_tutorial_on_home()
func show_settings():
	if _require_screen_name(): return
	if tutorial.active: return
	# A non-modal claim pop (z 30) would paint over the modal; it is only flavour, drop it.
	if cinematic.active and cinematic.kind == "pop": cinematic.clear()
	overlay = "settings"; thinking = false; _rebuild()
func _close_overlay():
	_code_taps = 0
	overlay = ""; _rebuild(); _schedule_ai()
func _leave_online():
	if is_instance_valid(demo_rival): demo_rival.leave(); demo_rival.queue_free()
	if is_instance_valid(transport): transport.leave(); transport.queue_free()
	demo_rival = null; transport = null; remote_ready = false
	chat_open = false; _prompt_key = ""
	if is_instance_valid(joined_timer): joined_timer.stop()
func request_online():
	if not _name_required() and _tutorial_gate(request_online): return
	_quiet_gameplay()
	if _require_screen_name("online"): return
	# Choose before matchmaking: a join can start the match immediately.
	_leave_online()
	_pending_game = {"mode":"online_lobby","mark":human_mark}; _select_player = 0
	open_character_select()
func request_resume():
	if _require_screen_name(): return
	if _tutorial_gate(request_resume): return
	if not profile.data.onboarded:
		_pending_game = {"mode":"resume","mark":human_mark}; open_character_select(); return
	resume_game()
func _quiet_gameplay():
	# Polling a waiting room must not resume the previous solo game or its audio.
	thinking = false; hint_busy = false; cinematic.clear(); callout.callout = ""
	sound.stop_playback()
func open_online():
	if _require_screen_name("online"): return
	if _tutorial_gate(open_online): return
	_quiet_gameplay()
	_leave_online(); message = ""; room_code = ""; _room_password = ""
	page = "online"; overlay = ""; online_state = "lobby"
	if not test_online_bypass and not _debug_capture: social.probe()
	if not test_online_bypass and not _debug_capture and not account.store.online_ready():
		message = "Syncing your screen name for online play…"; _rebuild(); account.sync_pending(); return
	_rebuild(); _refresh_lobby()
func _attach_transport(t):
	_leave_online(); transport = t
	end_message = ""; chat_open = false; chat_unread = 0; chat_muted = false; chat_blocked = false; chat_status = ""; _chat_draft = ""
	_prompt_sent = ""; _moved_turn = ""; _you_name = ""
	if t is HTTP:
		t.device_token = account.store.data.device_token
		t.online2 = social.online2(); t.chat_enabled = social.chat()
		if http_request_factory.is_valid():
			t.api.request_factory = http_request_factory; t.aux_api.request_factory = http_request_factory
			if not t.farewell_factory.is_valid():
				var factory = http_request_factory
				t.farewell_factory = func():
					var farewell = JsonAPI.new(); farewell.request_factory = factory; return farewell
		t.chat_received.connect(_chat_received)
		t.chat_failed.connect(func(text): chat_status = text; if is_instance_valid(chat_view): chat_view.set_status(text))
		t.chat_sent.connect(func(): _chat_draft = ""; chat_status = ""; if is_instance_valid(chat_view): chat_view.clear_draft(); chat_view.set_status(""))
		t.link_changed.connect(func(_down): queue_redraw())
		t.clock_changed.connect(_clock_changed)
	add_child(t)
	lobby_timer.stop(); online_api.cancel_all(); _lobby_pending = false
	t.player_name = str(settings.values.player_name)
	t.character_id = str(profile.data.character_id)
	t.character_received.connect(func(mark,id):
		if mark != t.seat:
			rival_character = Roster.canonical_id(id)
			hero_video.prefetch_pair(str(profile.data.character_id),rival_character))
	t.room_created.connect(func(code): room_code = code; online_state = "waiting"; message = ""; _rebuild())
	t.joined.connect(func(code,seat):
		room_code = code; human_mark = seat
		# A joiner whose room still reports waiting sees the same waiting screen.
		if t is HTTP and page == "online" and str(t.room.get("status","")) == "waiting" and online_state != "waiting":
			online_state = "waiting"; message = ""; _rebuild())
	t.opponent_joined.connect(_online_ready)
	t.rematch_changed.connect(func(_local,_remote): _result_controls_refresh())
	t.match_started.connect(func(seat,_round):
		human_mark = seat
		if remote_ready: _reset_online_match())
	t.move_received.connect(_receive_move)
	t.state_received.connect(_receive_state)
	t.opponent_left.connect(func():
		remote_ready = false; thinking = false; joined_timer.stop()
		message = end_message if not end_message.is_empty() else "Your opponent has left the room."
		if page == "online" and online_state == "joined": online_state = "waiting"
		_rebuild())
	t.error.connect(func(msg): message = msg; _rebuild())
	if t is HTTP: t.room_updated.connect(_online_room_update)
func create_online(demo: bool = false, private_game: bool = false, password: String = ""):
	if _require_screen_name("online"): return
	if not demo and not test_online_bypass and not account.store.online_ready(): open_online(); return
	if private_game and (password.is_empty() or password.length() > 64):
		message = "Use a private-room password with 1–64 characters."; _online_status(); return
	_attach_transport(Loopback.new() if demo else _new_http())
	if transport is HTTP: transport.private_room = private_game; transport.password = password
	transport.create_room()
func join_online(code: String, demo: bool = false, password: String = ""):
	if _require_screen_name("online"): return
	if not demo and not test_online_bypass and not account.store.online_ready(): open_online(); return
	_attach_transport(Loopback.new() if demo else _new_http())
	if transport is HTTP: transport.password = password
	transport.join_room(code)
func _new_http():
	return HTTP.new()
func invite_demo_rival():
	if not transport is Loopback: return
	demo_rival = Loopback.new(); demo_rival.player_name = "Legend · Demo"
	demo_rival.character_id = "auric_rex" if profile.data.character_id != "auric_rex" else "vesper_vale"
	add_child(demo_rival)
	demo_rival.join_room(room_code)
func _online_ready():
	if online_tournament.match_active:
		remote_ready = true; opponent_name = transport.remote_name; rival_character = transport.remote_character_id
		human_mark = transport.seat; _reset_online_match(); return
	remote_ready = true; opponent_name = transport.remote_name; rival_character = transport.remote_character_id
	human_mark = transport.seat
	# Protocol 2 shows "<Name> joined" with their hero first; round 1–4 servers keep round 4g's flow.
	if transport is HTTP and transport.online2 and page == "online" and online_state in ["lobby","waiting","private"]:
		online_state = "joined"; message = ""; _rebuild(); joined_timer.start(JOINED_BEAT); return
	_reset_online_match()
func _joined_beat_done():
	if page == "online" and online_state == "joined" and remote_ready and is_instance_valid(transport): _reset_online_match()
func _capabilities_changed(_caps: Dictionary):
	if _caps.has("account_deletion"): account.deletion_capable = _caps.account_deletion == true
	if transport is HTTP:
		transport.online2 = transport.online2 or social.online2(); transport.chat_enabled = social.chat()
	if page in ["online","game"] or overlay == "settings": _rebuild()
## Chat is offered only when the server advertises it; old servers never see a chat request.
func chat_capable() -> bool:
	return transport is HTTP and transport.chat_enabled
func chat_notice() -> String:
	if not test_online_bypass and not account.store.online_ready(): return "Create a screen name to chat"
	if not chat_capable(): return "Chat — update coming soon"
	match str(transport.room.get("status","")):
		"waiting", "": return "Chat opens when your rival joins"
		"closed": return "This room is closed"
	return ""
func chat_messages() -> Array:
	if not chat_capable(): return []
	if not (chat_muted or chat_blocked): return transport.chat_log
	return transport.chat_log.filter(func(m): return m.mine)
func toggle_chat():
	if not chat_capable(): return
	chat_open = not chat_open; chat_unread = 0
	if chat_open: chat_status = ""
	_rebuild()
func _chat_received(fresh: Array):
	for m in fresh:
		if not m.mine and not chat_muted and not chat_blocked and not chat_open: chat_unread += 1
	if is_instance_valid(chat_view): chat_view.set_messages(chat_messages())
	if controls.has("chat") and is_instance_valid(controls.chat): controls.chat.unread = chat_unread; controls.chat.queue_redraw()
func _chat_moderation(kind: String, reason: String, note: String):
	if not is_instance_valid(transport): return
	var who = opponent_name
	match kind:
		"mute", "unmute":
			chat_muted = kind == "mute"; chat_status = (who+" muted for this match") if chat_muted else (who+" unmuted")
			_show_chat_view("chat")
		"block":
			if not social.block(transport.code,3-transport.seat): chat_status = "Couldn't block right now."; _show_chat_view("block")
		"report":
			if not social.report(transport.code,3-transport.seat,reason,note): chat_status = "Couldn't send the report right now."; _show_chat_view("report")
func _show_chat_view(view: String):
	if not is_instance_valid(chat_view): return
	chat_view.muted = chat_muted; chat_view.blocked = chat_blocked; chat_view.messages = chat_messages()
	chat_view.show_view(view); chat_view.set_status(chat_status)
func _social_finished(kind: String, ok: bool, text: String):
	match kind:
		"block":
			if ok: chat_blocked = true; chat_status = opponent_name+" blocked"
			else: chat_status = text
			_show_chat_view("chat" if ok else "block")
		"report":
			chat_status = "Thanks — we'll review it" if ok else text
			_show_chat_view("chat" if ok else "report")
		"unblock", "blocks":
			blocked_status = "" if ok else text
			if kind == "unblock" and ok: social.fetch_blocks()
			if overlay == "blocked": _rebuild()
func open_blocked_players():
	if not social.chat(): return
	overlay = "blocked"; blocked_status = "Loading…" if social.fetch_blocks() else "Blocked players need an online screen name."; _rebuild()
## Turn key: one still-here and one "move dismisses the prompt" per server turn clock.
func _turn_key() -> String:
	return str(transport.room.get("turn_started_at","")) if transport is HTTP else ""
## Presentation never changes the server-owned turn or assumes the local seat is X.
func local_online_turn() -> bool:
	if not remote_ready or game.status != 0 or game.turn != human_mark: return false
	if transport is HTTP and (transport.reconnecting or transport._inflight == "move" or transport.turn_phase().phase == "expired"): return false
	return true
func online_turn_caption() -> String:
	if not remote_ready: return "Waiting for opponent"
	if transport is HTTP and transport.reconnecting: return "Reconnecting…"
	if transport is HTTP and transport._inflight == "move": return "Sending move…"
	if transport is HTTP and transport.turn_phase().phase == "expired": return "Checking result…"
	return "Your turn" if game.turn == human_mark else "Opponent's turn"
func _sync_turn_affordances():
	board.active_highlights_enabled = tutorial.active or mode != "online" or local_online_turn()
	board.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if board.active_highlights_enabled else Control.CURSOR_ARROW
	board.refresh()
func turn_info() -> Dictionary:
	if not transport is HTTP or mode != "online" or page != "game" or not remote_ready: return {"phase":"none","mine":false}
	return transport.turn_phase()
## "", "ask" (Still there? + I'm here) or "move" (Move now!, allowance used).
func prompt_state() -> String:
	if not transport is HTTP or not transport.online2 or game.status != 0 or tutorial.active: return ""
	if cinematic.active and cinematic.kind == "versus": return ""
	var info = turn_info()
	if info.phase != "still_there" or not info.mine: return ""
	if _moved_turn == _turn_key(): return ""
	if bool(transport.room.get("still_here_used",false)) or _prompt_sent == _turn_key(): return "move"
	return "ask"
func confirm_still_here():
	if not transport is HTTP: return
	if transport.still_here(): _prompt_sent = _turn_key()
	_prompt_key = prompt_state(); _rebuild()
func _clock_changed():
	var key = prompt_state()
	if key != _prompt_key: _prompt_key = key; _rebuild()
## Online status lines under the board: [primary, small secondary].
## Server-derived late-turn warning; counters belong to each seat, not the device.
func idle_turn_warning() -> String:
	if not transport is HTTP or str(transport.room.get("status","")) != "active": return ""
	var info = turn_info()
	var limit = int(transport.room.get("turn_late_limit",0))
	if limit <= 0 or info.phase not in ["turn","still_there"]: return ""
	var key = "consecutive_late_turns" if info.mine else "opponent_consecutive_late_turns"
	var late = int(transport.room.get(key,0))
	if late <= 0: return ""
	if info.phase == "turn" and late >= limit-1:
		return "Final warning: move in %s or lose" % Clock.mmss(info.remaining) if info.mine else "Opponent must move in %s or lose" % Clock.mmss(info.remaining)
	if late >= limit-1:
		return "Next late turn loses (%d/%d)" % [late,limit] if info.mine else "Opponent: next late turn loses (%d/%d)" % [late,limit]
	return "Late turns: %d/%d; a timely move resets" % [late,limit] if info.mine else "Opponent late turns: %d/%d" % [late,limit]
func online_lines() -> Array:
	if mode != "online" or page != "game" or game.status != 0: return ["",""]
	if not transport is HTTP: return [online_turn_caption(),""]
	if transport.reconnecting: return ["Reconnecting — timer continues",idle_turn_warning()]
	if transport._inflight == "move": return ["Sending move…",""]
	var info = turn_info()
	var first = "First moves — no-shows cancel with no loss" if transport.online2 and transport.room.has("both_moved") and not bool(transport.room.both_moved) and not bool(transport.room.get("still_here_used",false)) else ""
	var warning = idle_turn_warning()
	if not warning.is_empty(): first = warning
	if transport.room.get("opponent_connected") == false: return [opponent_name+" reconnecting…",first]
	match info.phase:
		"turn", "still_there":
			if info.mine: return ["Your move · "+Clock.mmss(info.remaining) if info.phase == "turn" else "",first]
			return ["Waiting for %s… %s" % [opponent_name,Clock.mmss(info.remaining)],first]
		"expired": return ["Time expired — checking result…",""]
		"legacy": return [online_turn_caption()+" · "+Clock.mmss(info.remaining),""]
	return [online_turn_caption(),first]
func toggle_match_sound():
	settings.set_value("sound",not bool(settings.values.sound))
	_apply_preferences()
	if controls.has("match_sound"):
		controls.match_sound.icon_kind = "sound_on" if sound.enabled else "sound_off"
		controls.match_sound.tooltip_text = "Mute sound" if sound.enabled else "Enable sound"
		controls.match_sound.queue_redraw()
func header_button_size() -> float:
	return 52.0 if layout.mode == "landscape" and layout.header.size.x >= 232 else 44.0
func header_button_gap() -> float:
	return 8.0 if layout.header.size.x >= 208 else 2.0
func match_sound_rect() -> Rect2:
	var hdr: Rect2 = layout.header
	var hb = header_button_size()
	return Rect2(hdr.position.x+hb+header_button_gap(),hdr.position.y,hb,hb)
func chat_button_rect() -> Rect2:
	var hdr: Rect2 = layout.header
	var hb = header_button_size()
	return Rect2(hdr.end.x-hb*2-header_button_gap(),hdr.position.y,hb,hb)
func _chat_button(rect: Rect2, z: int = 0):
	var b = ChatPanel.ChatButton.new(); b.name = "chat"; b.tooltip_text = "Chat"; b.unread = chat_unread
	b.position = rect.position; b.size = rect.size; b.z_index = z
	b.pressed.connect(func():
		_code_taps = 0
		sound.cue("ui")); b.pressed.connect(toggle_chat)
	add_child(b); ui_nodes.append(b); controls["chat"] = b
func _build_chat_panel(rect: Rect2, z: int = 40):
	chat_view = ChatPanel.new(); chat_view.position = rect.position; chat_view.size = rect.size; chat_view.z_index = z
	chat_view.messages = chat_messages(); chat_view.presets = social.presets(); chat_view.opponent_name = opponent_name if remote_ready or transport.chat_log.size() > 0 else ""
	chat_view.notice = chat_notice(); chat_view.can_send = chat_view.notice.is_empty()
	chat_view.can_moderate = remote_ready and (test_online_bypass or account.store.online_ready())
	chat_view.muted = chat_muted; chat_view.blocked = chat_blocked; chat_view.status = chat_status; chat_view.draft = _chat_draft
	chat_view.send_text.connect(func(text): if transport is HTTP: transport.send_chat(text))
	chat_view.send_preset.connect(func(key): if transport is HTTP: transport.send_chat("",key))
	chat_view.closed.connect(toggle_chat)
	chat_view.draft_changed.connect(func(text): _chat_draft = text)
	chat_view.moderation.connect(_chat_moderation)
	add_child(chat_view); ui_nodes.append(chat_view)
## Chat sheet and the "Still there?" prompt on the live board. The prompt wins the space.
func _online_game_chrome():
	_prompt_key = prompt_state()
	if not _prompt_key.is_empty(): _build_prompt(_prompt_key)
	elif chat_open and chat_capable(): _build_chat_panel(ChatPanel.panel_rect(layout))
func prompt_rect() -> Rect2:
	if layout.mode == "phone_portrait":
		var top = layout.board.end.y+4
		return Rect2(14,top,layout.size.x-28,clampf(layout.controls.end.y-top,86,104))
	var info: Rect2 = layout.get("info",Rect2())
	if info.size.x >= 220 and info.size.y >= 96: return Rect2(info.position,Vector2(info.size.x,minf(info.size.y,124)))
	var b: Rect2 = layout.board
	return Rect2(b.position.x+8,b.end.y-112,b.size.x-16,104)
func _build_prompt(state: String):
	var r = prompt_rect()
	prompt_layer = Layer.new(); prompt_layer.name = "StillThere"; prompt_layer.painter = _draw_prompt
	prompt_layer.position = r.position; prompt_layer.size = r.size; prompt_layer.z_index = 45; prompt_layer.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(prompt_layer); ui_nodes.append(prompt_layer)
	if state == "ask":
		var bw = minf(150,r.size.x*.4)
		var b = _button("still_here","I'm here",Rect2(r.end.x-bw-12,r.position.y+(r.size.y-52)*.5,bw,52),confirm_still_here,true)
		b.z_index = 46
func _draw_prompt(n: Control):
	var r = Rect2(Vector2.ZERO,n.size)
	var info = turn_info()
	var red = Clock.tier_color("red")
	var pulse = 1.0 if board.reduced_motion else .7+.3*sin(clock*TAU*1.2)
	P.box_glow(n,r,Color(red,.3*pulse),12,10)
	n.draw_colored_polygon(P.polygon(r.grow(-2)),Color(.03,.02,.04,.96))
	P.panel(n,r,false,1,true); P.outline(n,r.grow(-5),Color(red,.8*pulse),1.6)
	var ask = _prompt_key == "ask"
	var text_w = r.size.x-(minf(150,r.size.x*.4)+36 if ask else 32)
	var title = "Still there?" if ask else "Move now!"
	var tfs = P.fit_size(title,text_w-80,24,P.SERIF)
	var tw = P.text_width(title,tfs,P.SERIF)
	var top = (r.size.y-68)*.5
	P.text(n,title,Rect2(18,top,tw+8,36),tfs,P.PALE,P.SERIF,HORIZONTAL_ALIGNMENT_LEFT,.4)
	P.text(n,Clock.mmss(info.get("remaining",0.0)),Rect2(28+tw,top-2,72,40),28,red,P.SANS,HORIZONTAL_ALIGNMENT_LEFT)
	var hint = "Tap I'm here or make a move" if ask else "Move before time runs out or lose"
	P.text(n,hint,Rect2(18,top+40,text_w,24),P.fit_size(hint,text_w,15),P.MUTED,P.SANS,HORIZONTAL_ALIGNMENT_LEFT)
## Timer ring geometry around the active seat's portrait (for drawing and tests).
func ring_geometry(mark: int) -> Dictionary:
	var r: Rect2 = layout.players
	if layout.mode == "landscape":
		var hh = (r.size.y-52.0*_u())*.5
		var rr = Rect2(r.position,Vector2(r.size.x,hh)) if mark == human_mark else Rect2(r.position.x,r.end.y-hh,r.size.x,hh)
		var radius = minf(rr.size.x*.34,rr.size.y*.25)
		var center = Vector2(rr.get_center().x,rr.position.y+rr.size.y*.12+radius+14*_u())
		# Stay above the name line (drawn at 64% of the card) so the ring never crosses it.
		return {"center":center,"radius":minf(radius+8,rr.position.y+rr.size.y*.64-center.y-6)}
	var gap = minf(46,r.size.x*.12); var width = (r.size.x-gap)/2
	var side = Rect2(r.position,Vector2(width,r.size.y)) if mark == human_mark else Rect2(r.end.x-width,r.position.y,width,r.size.y)
	var g = scorecard_geometry(side,mark != human_mark)
	var radius = g.radius+maxf(2.5,g.radius*.13)*.5+2.2
	# Medallions can hang over their cards on Duo; keep the timer stroke on-screen.
	var edge = minf(minf(g.center.x,layout.size.x-g.center.x),minf(g.center.y,layout.size.y-g.center.y))
	return {"center":g.center,"radius":minf(radius,edge-4.5)}
func timer_ring_rect(mark: int) -> Rect2:
	var g = ring_geometry(mark); var reach = g.radius+4.0
	return Rect2(g.center-Vector2(reach,reach),Vector2(reach,reach)*2)
func timer_hud_visible() -> bool:
	return page == "game" and mode == "online" and game.status == 0 and overlay.is_empty() and not tutorial.active and not cinematic.active
func _draw_timer_hud(n: Control):
	if not timer_hud_visible(): return
	for mark in [1,2]: _draw_timer_ring(n,mark)
func timer_ring_info() -> Dictionary:
	var info = turn_info().duplicate()
	# Compatibility envelopes can have a real expiry but no prompt boundary.
	# Show their actual seconds, never invent a 25-second turn or a 10-second grace.
	if info.phase == "legacy":
		info.fraction = 1.0
		var start = Clock.parse(transport.room.get("turn_started_at"))
		var end = Clock.parse(transport.room.get("turn_expires_at"))
		if start > 0 and end > start: info.fraction = clampf(float(info.remaining)/(end-start),0,1)
		info.tier = "calm" if info.remaining > Clock.AMBER_AT else ("amber" if info.remaining > Clock.RED_AT else "red")
	return info
func _draw_timer_ring(n: Control, mark: int):
	var info = timer_ring_info()
	if not info.phase in ["turn","still_there","legacy"] or float(info.get("remaining",0)) <= 0 or int(info.get("turn",0)) != mark: return
	var g = ring_geometry(mark)
	var color = Clock.tier_color(info.tier)
	# Reduced motion: a steady ring. Otherwise amber/red breathe gently.
	var alpha = 1.0 if board.reduced_motion or info.tier == "calm" else .82+.18*sin(clock*TAU*1.5)
	var end = -PI*.5+TAU*float(info.fraction)
	# Strong dark rail + bright moving arc remain readable over any portrait palette.
	n.draw_arc(g.center,g.radius,0,TAU,96,Color(.01,.02,.05,.98),8,true)
	n.draw_arc(g.center,g.radius,0,TAU,96,Color(color,.22),5.5,true)
	n.draw_arc(g.center,g.radius,-PI*.5,end,96,Color(color,alpha),5.5,true)
	n.draw_circle(g.center+Vector2.from_angle(end)*g.radius,3.0,Color(color.lightened(.45),alpha))
	# Seconds belong beside the active face too, not only in the bottom status line.
	var badge = Rect2(g.center+Vector2(-16,g.radius-22),Vector2(32,19))
	n.draw_style_box(_timer_badge_style(),badge)
	P.text(n,str(maxi(0,ceili(float(info.remaining)-.001))),badge,15,color,P.SANS)
func _timer_badge_style() -> StyleBoxFlat:
	var style = StyleBoxFlat.new(); style.bg_color = Color(.01,.02,.05,.96)
	style.corner_radius_top_left = 5; style.corner_radius_top_right = 5
	style.corner_radius_bottom_left = 5; style.corner_radius_bottom_right = 5
	return style
func leave_costs_loss() -> bool:
	return transport.leave_costs_loss() if transport is HTTP else false
## In-game back: a live match asks first; the copy depends on both_moved.
func game_back():
	if mode == "online" and page == "game" and game.status == 0 and remote_ready and is_instance_valid(transport) and not tutorial.active and overlay.is_empty():
		chat_open = false; callout.callout = ""; overlay = "leave_confirm"; _rebuild(); return
	go_home()
func _reset_online_match():
	if _require_screen_name("online"): return
	if not test_online_bypass and not _debug_capture and not transport is Loopback and not account.store.online_ready(): open_online(); return
	hero_video.prefetch_pair(str(profile.data.character_id),rival_character)
	_spotlight_done = false; cinematic.clear(); _debug_capture = false; joined_timer.stop(); end_message = ""
	_prompt_sent = ""; _moved_turn = ""
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
		online_sequence = seq; _refresh_labels(); _refresh_history()
		if tutorial.active: return
		board.clear_effects(); _schedule_ai()
		if game.status != 0:
			board.start_win(game.big_lines[0] if not game.big_lines.is_empty() else [],game.status)

func _online_room_update(data: Dictionary):
	if online_tournament.match_active: online_tournament.match_ended(data)
	var you = data.get("you")
	if you is Dictionary and you.get("name") is String and not str(you.name).is_empty(): _you_name = str(you.name)
	if is_instance_valid(transport) and not transport.remote_name.is_empty() and transport.remote_name != "Remote player": opponent_name = transport.remote_name
	var reason = str(data.get("end_reason")) if data.get("end_reason") is String else ""
	if data.get("status","") == "closed" and end_message.is_empty() and not reason.is_empty():
		var winner = int(data.result.get("winner",-1)) if data.get("result") is Dictionary else -1
		end_message = Clock.end_text(reason,winner,transport.seat if is_instance_valid(transport) else human_mark,bool(data.get("opponent_left",false)),opponent_name)
		if not end_message.is_empty():
			message = end_message
			if winner == -1 and page == "game" and not tutorial.active:
				# No recorded result: a clear "cancelled, no loss" card instead of a winner.
				remote_ready = false; thinking = false; chat_open = false; callout.callout = ""; overlay = "online_end"; _rebuild()
			elif winner == -1 and page == "online": online_state = "waiting" if online_state == "joined" else online_state; _rebuild()
	# Forfeits/timeouts are authoritative full-match results, outside board mechanics.
	var result = data.get("result")
	if data.get("status","") in ["finished","closed"] and result is Dictionary and (game.status == 0 or (online_tournament.match_active and game.status == 3)):
		var winner = int(result.get("winner",-1))
		if winner in [0,1,2]:
			game.status = 3 if winner == 0 else winner; thinking = false
			if not tutorial.active: board.start_win([],game.status)
			_refresh_labels()
	if online_tournament.match_active and data.get("status","") in ["finished","closed"] and result is Dictionary and not _result_shown:
		_show_spotlight()
	if data.get("status","") == "closed" and page == "online":
		message = end_message if not end_message.is_empty() else "This room is closed. Return to the lobby to play again."; _online_status()
	if page == "game" and overlay == "result" and not end_message.is_empty(): _result_controls_refresh()
func _name_required() -> bool:
	return not test_online_bypass and not _debug_capture and not account.store.complete() and not account.store.data.deletion_uncertain and not account.store.data.signed_out
func _require_screen_name(destination: String = "title") -> bool:
	if not _name_required(): return false
	if page != "onboarding" or not overlay.is_empty(): _show_onboarding(destination)
	elif destination == "online": _onboarding_destination = destination
	return true
func _notification(what: int):
	# Backgrounded/unfocused: keep polling, slower, so a brief app switch stays inside the grace.
	if what in [NOTIFICATION_APPLICATION_FOCUS_OUT,NOTIFICATION_APPLICATION_PAUSED] and transport is HTTP: transport.set_background(true)
	elif what in [NOTIFICATION_APPLICATION_FOCUS_IN,NOTIFICATION_APPLICATION_RESUMED] and transport is HTTP: transport.set_background(false)
	if what in [NOTIFICATION_WM_GO_BACK_REQUEST,NOTIFICATION_WM_CLOSE_REQUEST] and is_node_ready():
		if _require_screen_name(): return
		get_tree().quit()
func _show_onboarding(destination: String):
	_tutorial_continue = Callable()
	_leave_online(); _onboarding_destination = destination; page = "onboarding"; overlay = ""
	_pending_game = {}; _select_player = 0; thinking = false; hint_busy = false
	if tutorial.active:
		tutorial.active = false; tutorial.hide(); board.game = game
	_onboarding_name = account.store.data.screen_name; message = ""; cinematic.clear(); _rebuild()
func _recovery_action(kind: String):
	match kind:
		"send": recovery.request_code()
		"confirm": recovery.confirm()
		"cancel": recovery.cancel(); _onboarding_create = false; page = "onboarding"; _rebuild()
func _account_recovered(token: String, player: Dictionary):
	if page != "recovery": return
	# Server-confirmed existing identity only. No /auth/device registration here.
	account.api.cancel_all(); account.busy = false; account._refreshing = false
	account._tutorial_inflight = false; account._tutorial_owner = ""
	account.store.data.pending_hero = ""; account.store.data.pending_hero_owner = ""; account._hero_inflight = ""
	account.store.data.signed_out = false
	account.store.keep_device(token,str(player.screen_name))
	for key in ["tos_version","privacy_version","accepted_at","age_confirmed"]:
		account.store.data[key] = player[key] if typeof(player.get(key)) == typeof(account.store.data[key]) else (false if key == "age_confirmed" else "")
	account.store.data.pending_sync = false; account.store.data.registration_rejected = false; account.store.set_deletion_uncertain(false)
	account.store.data.email = ""; account.store.data.email_prompt_done = true
	account._accept_email_player(player,true); account.store.save()
	_hero_changed = false
	profile.data.character_id = "vesper_vale"
	_account_name(str(player.screen_name)); _account_player(player)
	if not account.store.complete():
		# Old consent must be renewed, but with this token, never a new identity.
		page = "onboarding"; _onboarding_create = true; _onboarding_name = str(player.screen_name)
		message = "Welcome back. Confirm your screen name to accept the current terms."; _rebuild(); return
	if _onboarding_destination == "online": request_online()
	else: go_home()
func _deletion_action(kind: String):
	if overlay == "local_reset":
		match kind:
			"review": deletion.proceed()
			"cancel": deletion.cancel(); overlay = "account_options"; _rebuild()
			"submit":
				if deletion.stage == 2 and not deletion.busy and deletion.phrase == "CLEAR THIS DEVICE":
					deletion.cancel(); _clear_local_account(false)
		return
	match kind:
		"review": deletion.proceed()
		"submit":
			if account.busy or account.email_busy or account.rename_pending() or not account.api._current.is_empty():
				deletion.message = "Wait for your account changes to finish, then try again."; deletion.changed.emit(); return
			deletion.submit(str(account.store.data.device_token),(account.deletion_capable or account.store.data.deletion_uncertain) and account.store.has_device_token())
		"cancel":
			if deletion.busy: return
			deletion.cancel(); overlay = "settings"; _rebuild()
func _retire_account_client(node: Node):
	node.set_block_signals(true); node.set_process(false)
	for child in node.get_children(): _retire_account_client(child)
func _account_status_copy() -> String:
	if account.store.data.pending_sync or not account.store.has_device_token():
		return "Local-only profile. Server registration is still pending; progress may not be backed up."
	return "Server account · verified recovery email" if account.store.data.email_status == "verified" else "Server account · recovery email not verified this session"
func _signout_copy() -> String:
	var copy = _account_status_copy()+"\n\nSign out on this device? Your server account is NOT deleted. Local profile and saved game details will be cleared."
	if account.store.data.email_status != "verified" or account.store.data.pending_sync or not account.store.has_device_token():
		copy += "\n\nWARNING: Without a verified recovery email, you may permanently lose access to this profile. Stay signed in and verify an email first if you want to keep it."
	else: copy += "\n\nUse your verified email to sign back in, or choose a different account."
	copy += "\n\nAny active match will disconnect and may count as a loss."
	if account.busy or account.email_busy or account.rename_pending() or not account.api._current.is_empty():
		copy = "Wait for your account changes to finish before signing out.\n\n"+copy
	return copy
func _confirm_signout():
	# Recheck synchronous cross-tab state at the action boundary, not just when
	# the confirmation opened. Never overwrite another tab's pending deletion.
	account.store.merge_deletion_marker()
	if account.store.data.deletion_uncertain or account.store.deletion_reset_required or deletion.busy:
		overlay = "account_options"; _rebuild(); return
	if account.busy or account.email_busy or account.rename_pending() or not account.api._current.is_empty():
		message = "Wait for your account changes to finish, then try again."; _rebuild(); return
	_clear_local_account(false,true)
func _new_account_after_signout():
	account.store.data.signed_out = false
	if not account.store.save():
		account.store.data.signed_out = true; return
	_onboarding_create = true
	_show_onboarding("title")
func _account_deleted():
	_clear_local_account(true)
func _clear_local_account(deletion_confirmed: bool, signed_out: bool = false):
	_code_pending = false; _code_owner = ""
	settings.values.unlocked_backgrounds = []
	settings.values.unlocked_heroes = []
	if not Themes.valid(str(settings.values.background_theme),Themes.BACKGROUNDS): settings.set_value("background_theme","crystal")
	_tutorial_continue = Callable(); _tutorial_waiting = false
	# Reached after precise server deletion success OR explicit typed local reset.
	# Retire request owners rather than letting late callbacks restore old identity.
	var account_path = account.store.path
	var marker_io = account.store.deletion_marker_io
	var account_factory = account.api.request_factory
	account.api.cancel_all(); _retire_account_client(account); remove_child(account); account.queue_free()
	account = DeviceAccount.new(); account.store = DeviceAccount.Store.new(account_path); account.store.deletion_marker_io = marker_io
	for key in account.store.data:
		account.store.data[key] = false if account.store.data[key] is bool else ""
	account.store.data.signed_out = signed_out
	var reset_persisted = account.store.mark_deletion_resolved(deletion_confirmed,"signedout" if signed_out else ("" if deletion_confirmed else "cleared"))
	deletion.store = account.store; account.api.request_factory = account_factory
	account.onboarding_complete.connect(_account_completed); account.sync_finished.connect(_account_sync_finished)
	account.name_updated.connect(_account_name); account.player_received.connect(_account_player)
	account.rename_flow_changed.connect(_settings_name_status); account.email_flow_changed.connect(_account_email_flow_changed)
	account.email_verified.connect(_account_email_verified); account.error.connect(_account_error); account.api.completed.connect(_code_completed); add_child(account)
	recovery.cancel(); online_api.cancel_all(); lobby_timer.stop(); joined_timer.stop()
	var lobby_factory = online_api.request_factory
	_retire_account_client(online_api); remove_child(online_api); online_api.queue_free()
	online_api = JsonAPI.new(); online_api.request_factory = lobby_factory; online_api.completed.connect(_online_response); add_child(online_api)
	social.api.cancel_all(); _retire_account_client(social); remove_child(social); social.queue_free()
	social = Social.new(); social.store = account.store
	if http_request_factory.is_valid(): social.api.request_factory = http_request_factory
	social.capabilities_changed.connect(_capabilities_changed)
	social.blocks_changed.connect(func(_names): blocked_status = "" ; if overlay == "blocked": _rebuild())
	social.finished.connect(_social_finished); add_child(social); account.player_received.connect(social.merge_player)
	# No leave POST after deletion: the server has already finished the operation.
	for client in [transport,demo_rival]:
		if is_instance_valid(client): _retire_account_client(client); remove_child(client); client.queue_free()
	transport = null; demo_rival = null; remote_ready = false
	online_tournament.timer.stop(); online_tournament.api.cancel_all(); _retire_account_client(online_tournament)
	remove_child(online_tournament); online_tournament.queue_free()
	online_tournament = preload("res://tournament/online_flow.gd").new(); add_child(online_tournament); online_tournament.setup(self)
	tournament.session.active = {}; tournament.session.wins = {}; tournament.session.last_events = []; tournament.session.save()
	tournament.match_active = false; tournament.pending_events = []
	profile.data = {"version":1,"identity":{},"display_name":"You","character_id":"vesper_vale","onboarded":false}; profile.save()
	settings.values.player_name = "You"; settings.saved_game = {}; settings.save()
	_onboarding_create = false
	_onboarding_name = ""; _email_draft = ""; _email_code_draft = ""; _name_draft = ""; _you_name = ""
	_room_entry = ""; _room_password = ""; room_code = ""; chat_open = false; _prompt_key = ""
	leaderboard_me = {}; leaderboard_players = []; public_rooms = []
	_chat_draft = ""; chat_status = ""; blocked_status = ""; end_message = ""; opponent_name = "Remote player"
	chat_unread = 0; chat_muted = false; chat_blocked = false; _prompt_sent = ""; _moved_turn = ""; _lobby_pending = false
	game = Rules.new(); board.game = game; board.clear_effects()
	_pending_game = {}; thinking = false; hint_busy = false; cinematic.clear()
	page = "onboarding"; overlay = ""; message = "Your account was deleted." if deletion_confirmed else "Local account details cleared. Earlier server deletion remains unconfirmed."
	if signed_out:
		page = "account_choice"; message = "Signed out. Your server account has not been deleted."
	if not reset_persisted:
		page = "title"; overlay = "account_options"
		message = "Local reset could not be saved. Automatic account creation remains blocked. Retry clearing this device."
	_rebuild()
func _account_name(value: String):
	settings.set_value("player_name",value); profile.data.display_name = value; profile.save()
	if overlay == "settings" and controls.has("player_name") and not account.rename_pending():
		controls.player_name.text = value
func _account_player(player: Dictionary):
	settings.values.unlocked_heroes = player.get("unlocked_heroes",[]) if player.get("unlocked_heroes") is Array else []
	if not Roster.selectable(str(profile.data.character_id),settings.values.unlocked_heroes):
		profile.data.character_id = "cryon"; _hero_focus = ""; profile.save()
	settings.values.unlocked_backgrounds = player.get("unlocked_backgrounds",[]) if player.get("unlocked_backgrounds") is Array else []
	if not Themes.valid(str(settings.values.background_theme),Themes.available(settings.values.unlocked_backgrounds)):
		settings.set_value("background_theme","crystal")
	_apply_preferences()
	call_deferred("_tutorial_on_home")
	var pending = account.pending_hero()
	var id = pending if not pending.is_empty() else str(player.get("last_hero_id",""))
	if not _hero_changed and Roster.selectable(id,settings.values.unlocked_heroes):
		profile.data.character_id = Roster.canonical_id(id); profile.save()
		if page == "character_select": _hero_focus = profile.data.character_id; _rebuild()
func _account_completed():
	message = ""
	if page != "onboarding": return
	page = "email"; _email_draft = account.store.data.email; _rebuild()
func _account_sync_finished():
	call_deferred("_tutorial_on_home")
	if _require_screen_name("online" if page == "online" else "title"): return
	if page != "online": return
	message = "" if account.store.online_ready() else "Your screen name is saved on this device. Online server not available. Open Online again to retry."
	_rebuild()
	if account.store.online_ready(): _refresh_lobby()
func _account_error(value: String):
	call_deferred("_tutorial_on_home")
	_require_screen_name("online" if page == "online" else "title")
	message = value
	if page == "email" or overlay == "account":
		if is_instance_valid(email_view): email_view.set_status(message)
	elif page == "onboarding":
		if is_instance_valid(online_view):
			online_view.set_status(message)
			if online_view.controls.has("create_name"): online_view.controls.create_name.disabled = false
	elif overlay == "settings": _settings_name_status()
	elif page == "online": _online_status()
func open_account_email():
	if _require_screen_name(): return
	_email_draft = account.store.data.email; message = ""; overlay = "account"; thinking = false; _rebuild()
func _account_email_flow_changed():
	if account.email_challenge.is_empty(): _email_code_draft = ""
	if page != "email" and overlay != "account": return
	message = account.email_message
	_rebuild()
func _account_email_verified():
	# Only the explicit confirmation submitted from onboarding may navigate.
	# A Settings confirmation or a late reply after leaving must not steal focus.
	if not _onboarding_email_confirmation or page != "email": return
	_onboarding_email_confirmation = false
	if _onboarding_destination == "online": request_online()
	else: go_home()
func _email_action(kind: String, value: String):
	if _require_screen_name(): return
	if kind == "save_email":
		if not account.save_email(value): return
		_email_draft = account.store.data.email
		# Saving is not a navigation action during onboarding. Account setup may
		# still be in flight; its completion will open the code-entry stage.
		if page == "email" or account.email_busy or account.email_pending: return
	elif kind == "confirm_email":
		account.confirm_email(value)
		_onboarding_email_confirmation = page == "email" and account.email_busy
		return
	elif kind == "resend_email": _email_code_draft = ""; account.request_email_verification(); return
	elif kind == "change_email": _email_code_draft = ""; account.edit_email(); return
	elif kind == "continue_email":
		_onboarding_email_confirmation = false
		if page == "email": account.continue_without_email()
	else: return
	if page == "email":
		if _onboarding_destination == "online": request_online()
		else: go_home()
	else:
		message = account.email_message if kind == "save_email" else ""
		overlay = "settings"; _rebuild()
func _build_email_screen(s: Vector2):
	# Block keyboard focus as well as pointer input on the screen underneath.
	for item in controls.values(): item.release_focus(); item.focus_mode = Control.FOCUS_NONE
	email_view = EmailScreen.new(); email_view.size = s; email_view.email = _email_draft
	email_view.set_verification_status(account.store.data.email_status)
	email_view.code = _email_code_draft; email_view.challenge = account.email_challenge
	email_view.busy = account.email_busy; email_view.pending = account.email_pending; email_view.retry_until = account.email_retry_until
	email_view.onboarding = page == "email"; email_view.status = message; email_view.z_index = 70
	email_view.action.connect(_email_action); email_view.draft_changed.connect(func(value): _email_draft = value)
	email_view.code_changed.connect(func(value): _email_code_draft = value)
	add_child(email_view); ui_nodes.append(email_view); controls.merge(email_view.controls,true)
func _tutorial_on_home():
	if _tutorial_waiting and not account._refreshing and not account.busy:
		_tutorial_waiting = false
		var next = _tutorial_continue; _tutorial_continue = Callable()
		if next.is_valid(): next.call_deferred(); return
	if page != "title" or not overlay.is_empty() or account._refreshing or account.busy: return
	if account.store.complete(): _tutorial_gate(Callable())
func _tutorial_gate(next: Callable) -> bool:
	if test_online_bypass or _debug_capture or account.store.data.tutorial_completed: return false
	# Never interrupt a live match, including a resumed tournament match.
	if mode == "online" and page == "game" and game.status == 0: return false
	if tutorial.active: return true
	if _name_required(): return false
	_tutorial_continue = next
	if account._refreshing:
		_tutorial_waiting = true; return true
	start_tutorial()
	return tutorial.active
func _maybe_tutorial() -> bool:
	# Retained for QA callers; automatic tutorials no longer run after versus.
	return _tutorial_gate(Callable())
func start_tutorial(replay: bool = false):
	if _require_screen_name(): return
	if tutorial.active: return
	if mode == "online" and page == "game" and game.status == 0: return
	_tutorial_return_overlay = overlay if replay else ""
	thinking = false; hint_busy = false; sound.clear_announcer(); callout.callout = ""
	# A non-modal claim animation must not cover or finish during the demo.
	if cinematic.active and cinematic.kind == "pop": cinematic.clear()
	overlay = "tutorial"; tutorial.begin(board,layout,replay); _rebuild()
func _tutorial_finished(_skipped: bool):
	account.complete_tutorial()
	board.game = game; board.clear_effects(); board.hint_move = Vector2i(-1,-1)
	_skip_guard_until = Time.get_ticks_msec()+SKIP_GUARD_MS
	overlay = _tutorial_return_overlay; _refresh_labels(); _rebuild(); _schedule_ai()
	var next = _tutorial_continue; _tutorial_continue = Callable()
	if next.is_valid():
		next.call_deferred(); return
	if page == "game" and game.status != 0 and overlay.is_empty():
		board.start_win(game.big_lines[0] if not game.big_lines.is_empty() else [],game.status)
	elif page == "game" and overlay.is_empty(): _announce("ready")
func _settings_name_status():
	if overlay != "settings": return
	if controls.has("name_status"): controls.name_status.text = account.rename_message
	if controls.has("save_name"): controls.save_name.disabled = account.rename_pending()
	if controls.has("player_name"): controls.player_name.editable = not account.rename_pending()
func _online_status():
	if is_instance_valid(online_view): online_view.set_status(message)
func _refresh_lobby():
	if test_online_bypass or _debug_capture or page != "online" or online_state != "lobby" or _lobby_pending: return
	if _require_screen_name("online") or not account.store.online_ready(): return
	_lobby_pending = true
	online_api.submit("/rooms",HTTPClient.METHOD_GET,{},"lobby",account.store.data.device_token)
func open_leaderboard():
	if _require_screen_name("online"): return
	if not test_online_bypass and not _debug_capture and not account.store.online_ready(): open_online(); return
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
	if kind in ["begin_create","account_back"]:
		if account.busy: return
		_onboarding_create = kind == "begin_create"; message = ""; _rebuild(); return
	if kind == "sign_in":
		if account.busy: return
		recovery.begin(); page = "recovery"; message = ""; _rebuild(); return
	if kind != "register" and _require_screen_name("online" if kind != "home" else "title"): return
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
		"chat": toggle_chat()
func _online_draft(kind: String, value: String):
	match kind:
		"screen_name": _onboarding_name = value
		"room_code": _room_entry = value
		"password": _room_password = value
func _build_online_screen(s: Vector2):
	online_view = OnlineScreen.new(); online_view.size = s
	online_view.screen = page if page in ["onboarding","leaderboard"] else ("waiting" if online_state == "joined" else online_state)
	if page == "onboarding" and not _onboarding_create: online_view.screen = "account_welcome"
	online_view.joined = online_state == "joined"; online_view.hero_id = str(profile.data.character_id)
	if remote_ready and is_instance_valid(transport): online_view.opponent_name = opponent_name; online_view.opponent_hero = rival_character
	online_view.chat_button = chat_capable() and online_state in ["waiting","joined"]; online_view.chat_unread = chat_unread
	online_view.reduced_motion = board.reduced_motion
	online_view.screen_name = _onboarding_name if page == "onboarding" else str(account.store.data.screen_name)
	if page == "online" and online_view.screen_name.is_empty(): online_view.screen_name = _you_name if not _you_name.is_empty() else str(settings.values.player_name)
	online_view.room_code = room_code if online_state in ["waiting","joined"] else _room_entry
	online_view.password = _room_password; online_view.status = message; online_view.rooms = public_rooms
	online_view.players = leaderboard_players; online_view.me = leaderboard_me
	online_view.local_demo = transport is Loopback
	online_view.private_room = transport.private_room if transport is HTTP else false
	online_view.busy = account.busy
	online_view.action.connect(_online_action); online_view.draft_changed.connect(_online_draft)
	add_child(online_view); ui_nodes.append(online_view); controls.merge(online_view.controls)
	if page == "online" and online_state in ["waiting","joined"] and chat_open and chat_capable():
		var wide = s.x > s.y
		_build_chat_panel(Rect2(s.x*.5+8,8,s.x*.5-16,s.y-16) if wide else Rect2(8,s.y*.44,s.x-16,s.y*.56-8))

func _clear_nodes():
	for n in ui_nodes:
		if is_instance_valid(n): remove_child(n); n.queue_free()
	ui_nodes.clear(); controls.clear(); online_view = null; email_view = null; chat_view = null; prompt_layer = null; history_label = null; _result_bases.clear(); field_heroes.clear(); hero_select = null
func _button(id: String, caption: String, rect: Rect2, callback: Callable, accent: bool = false, icon: String = ""):
	var b = OrnateButton.new(); b.name = id; b.caption = caption; b.tooltip_text = caption if not caption.is_empty() else id.capitalize()
	b.icon_kind = icon
	b.position = rect.position; b.size = rect.size; b.accent = accent
	b.font_size = int(clampf(rect.size.y*.4,17,26))
	b.pressed.connect(func():
		if id != "difficulty": _code_taps = 0
		sound.cue("ui")); b.pressed.connect(callback); add_child(b); ui_nodes.append(b); controls[id] = b
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
func _modal_label(value: String, rect: Rect2, font_size: int, color: Color) -> Label:
	var label = Label.new(); label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; label.text = value
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_override("font",P.SANS); label.add_theme_font_size_override("font_size",font_size); label.add_theme_color_override("font_color",color)
	# Size last: before autowrap is on, the unwrapped text would force a wider minimum.
	label.position = rect.position; label.size = rect.size
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE; add_child(label); ui_nodes.append(label)
	return label
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
	if account.store.data.signed_out and page != "recovery" and not account.store.data.deletion_uncertain:
		page = "account_choice"; overlay = ""
	if page != "recovery" and recovery.active: recovery.cancel()
	if page != "email": _onboarding_email_confirmation = false
	if not is_instance_valid(board): return
	if _name_required() and (page not in ["onboarding","recovery"] or not overlay.is_empty()):
		_show_onboarding("title"); return
	_clear_nodes()
	board.visible = page == "game" or tutorial.active
	board.mouse_filter = Control.MOUSE_FILTER_STOP if overlay.is_empty() else Control.MOUSE_FILTER_IGNORE
	backdrop.title_mode = page != "game" and not tutorial.active
	title_label.visible = page == "title" and not tutorial.active
	var s: Vector2 = layout.size
	if page == "title": _title_controls(s)
	elif page == "account_choice":
		var w = minf(420,s.x-48); var x = (s.x-w)*.5; var y = maxf(48,s.y*.3)
		_modal_label("SIGNED OUT",Rect2(x,y,w,48),28,P.PALE)
		_button("sign_in","Sign in",Rect2(x,y+68,w,52),func(): recovery.begin(); page = "recovery"; _rebuild(),true)
		_button("new_account","New account",Rect2(x,y+132,w,52),_new_account_after_signout)
	elif page == "character_select":
		hero_select = HeroSelect.new(); hero_select.unlocked_heroes = settings.values.unlocked_heroes; hero_select.size = s; hero_select.hinge = layout.hinge
		hero_select.selected_id = _hero_focus if not _hero_focus.is_empty() else str(profile.data.character_id)
		hero_select.display_name = _name_draft if not _name_draft.is_empty() else str(profile.data.display_name)
		hero_select.reduced_motion = board.reduced_motion
		hero_select.trophy_counts = tournament.session.wins
		hero_select.heading = "PLAYER %d · CHOOSE HERO" % _select_player if _select_player > 0 else "CHOOSE YOUR HERO"
		if _pending_game.get("mode","") == "online_lobby":
			hero_select.heading = "ONLINE · CHOOSE YOUR HERO"
			hero_select.confirm_caption = "CONTINUE"
		hero_select.blocked_id = str(profile.data.character_id) if _select_player == 2 else ""
		if _select_player > 0: hero_select.display_name = "PLAYER %d" % _select_player
		hero_select.focused.connect(func(id): hero_video.prefetch_hero(id); _hero_changed = true; _hero_focus = id; sound.prepare_character(Roster.audio_index(id)); sound.cue("ui",-.35))
		hero_select.name_changed.connect(func(value): _name_draft = value)
		hero_select.confirmed.connect(_confirm_hero)
		hero_select.back.connect(func(): _pending_game = {}; go_home())
		hero_video.prefetch_hero(hero_select.selected_id)
		add_child(hero_select); ui_nodes.append(hero_select)
		if _select_player > 0: hero_select.field.editable = false
	elif page == "tournament": tournament.build(s)
	elif page == "online_tournament": online_tournament.build(s)
	elif page == "game":
		var hdr: Rect2 = layout.header
		var big = layout.mode == "landscape"
		var hb = header_button_size()
		_button("home","" if not big else "",Rect2(hdr.position,Vector2(hb,hb)),game_back,false,"home" if big else "back")
		_button("settings","⚙",Rect2(Vector2(hdr.end.x-hb,hdr.position.y),Vector2(hb,hb)),show_settings)
		var mute = _button("match_sound","",match_sound_rect(),toggle_match_sound,false,"sound_on" if sound.enabled else "sound_off")
		mute.tooltip_text = "Mute sound" if sound.enabled else "Enable sound"
		if mode == "online" and chat_capable(): _chat_button(chat_button_rect())
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
		if mode == "online" and overlay.is_empty(): _online_game_chrome()
	elif page in ["online","onboarding","leaderboard"]: _build_online_screen(s)
	elif page == "email": _build_email_screen(s)
	elif page == "recovery":
		var view = RecoveryScreen.new(); view.size = s; view.flow = recovery; view.action.connect(_recovery_action)
		add_child(view); ui_nodes.append(view); controls.merge(view.controls)
	if is_instance_valid(lobby_timer):
		if page == "online" and online_state == "lobby" and not test_online_bypass and not _debug_capture and account.store.online_ready():
			if lobby_timer.is_stopped(): lobby_timer.start()
		else:
			lobby_timer.stop(); online_api.cancel_all(); _lobby_pending = false
	if overlay == "tutorial":
		for item in controls.values():
			item.release_focus(); item.focus_mode = Control.FOCUS_NONE
			item.mouse_filter = Control.MOUSE_FILTER_IGNORE
			item.visible = false
		# Game chrome is added after the tutorial node; later siblings can steal
		# clicks on web even when the tutorial has a higher z_index. Keep it on top
		# and exclusive for input. Home/Settings/Undo/Hint also overlapped Skip/Next.
		move_child(tutorial,get_child_count()-1)
		tutorial.relayout(layout)
	elif overlay in ["delete_account","local_reset"]:
		for item in controls.values():
			item.release_focus(); item.focus_mode = Control.FOCUS_NONE; item.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var view = DeletionScreen.new(); view.size = s; view.flow = deletion; view.local_only = overlay == "local_reset"; view.z_index = 100
		view.action.connect(_deletion_action); add_child(view); ui_nodes.append(view); controls.merge(view.controls)
	elif overlay == "account": _build_email_screen(s)
	elif overlay == "result": _winner_controls(s); _result_chat()
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
	items.insert(1,["tournament","Tournament" if tournament.session.active.is_empty() else "Resume Tournament",func():
		if not _require_screen_name(): online_tournament.request(),false])
	if not settings.saved_game.is_empty(): items.append(["resume","Resume Journey",request_resume,false])
	var bh = clampf(s.y*.064,44,58)
	if _title.hinge:
		var menu_x = layout.hinge.end.x+12; var bw = minf(320,s.x-menu_x-12)
		var gap = bh+10
		var y = (s.y-(gap*(items.size()+1)))/2
		for item in items:
			_button(item[0],item[1],Rect2(menu_x,y,bw,bh),item[2],item[3]); y += gap
		_button("settings","Settings",Rect2(menu_x,y,bw*.48,44),show_settings)
		_button("how","How to Play",Rect2(menu_x+bw*.52,y,bw*.48,44),func(): start_tutorial(true))
	elif _title.landscape:
		bh = clampf(s.y*.12,44,58)
		var columns = 3 if s.y < 420 else 2
		var bw = minf(310,(s.x-40-(columns-1)*12)/columns); var gap = bh+(8 if s.y < 420 else 14)
		items.append(["settings","Settings",show_settings,false])
		items.append(["how","How to Play",func(): start_tutorial(true),false])
		var y = maxf(_title.tagline.end.y+(8 if s.y < 420 else 12),s.y*.4 if s.y >= 420 else 0)
		for i in range(items.size()):
			var item = items[i]
			var x = (s.x-(bw*columns+(columns-1)*12))*.5+(i%columns)*(bw+12)
			_button(item[0],item[1],Rect2(x,y+int(i/columns)*gap,bw,bh),item[2],item[3])
	else:
		var bw = minf(330,s.x-64); var gap = bh+10
		var y = maxf(s.y*.47,_title.tagline.end.y+s.y*.14)
		var x = (s.x-bw)/2
		for item in items:
			_button(item[0],item[1],Rect2(x,y,bw,bh),item[2],item[3]); y += gap
		_button("settings","Settings",Rect2(x,y,bw*.48,44),show_settings)
		_button("how","How to Play",Rect2(x+bw*.52,y,bw*.48,44),func(): start_tutorial(true))
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
	var short = s.x > s.y and (s.y < 500 or (overlay == "settings" and not layout.hinge.has_area()))
	var pw = minf(740 if short else 480,s.x-28); var ph = minf(600,s.y-24)
	if overlay == "setup": ph = minf(410,s.y-24)
	if overlay == "settings" and not short: ph = minf(670,s.y-24)
	if overlay == "result": pw = minf(pw,460); ph = minf(340,s.y-24)
	if overlay in ["leave_confirm","online_end"]: pw = minf(440,s.x-28); ph = minf(300,s.y-24)
	if overlay == "blocked": pw = minf(460,s.x-28); ph = minf(480,s.y-24)
	_modal_rect = Rect2((s.x-pw)/2,(s.y-ph)/2,pw,ph)
	if layout.hinge.size.x > 0:
		pw = minf(pw,s.x-layout.hinge.end.x-24)
		_modal_rect = Rect2(layout.hinge.end.x+12,(s.y-ph)/2,pw,ph)
	# Modal painting belongs above the shield and all underlay controls.
	var painter = Control.new(); painter.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	painter.mouse_filter = Control.MOUSE_FILTER_IGNORE; painter.draw.connect(_draw_modal.bind(painter)); add_child(painter); ui_nodes.append(painter)
	var r = _modal_rect
	if overlay not in ["result","online_end"]: _button("close","×",Rect2(r.end.x-56,r.position.y+10,44,44),(func(): overlay = "settings"; _rebuild()) if overlay == "blocked" else _close_overlay)
	if overlay == "setup":
		var y = r.position.y+(76 if short else 94); var step = (pw-56)/3
		for i in range(3):
			var level = ["Easy","Medium","Hard"][i]
			_button("difficulty_"+level,level,Rect2(r.position.x+20+i*step,y,step-8,48),func(): settings.set_value("difficulty",level); _rebuild(),settings.values.difficulty == level)
		_button("choose_x","Play first",Rect2(r.position.x+24,y+(60 if short else 88),pw-48,48 if short else 56),func(): request_game("computer",1),true,"x")
		_button("choose_o","Play second",Rect2(r.position.x+24,y+(118 if short else 156),pw-48,48 if short else 56),func(): request_game("computer",2),false,"o")
	elif overlay == "settings":
		var sw = (pw-88)/3 if short else pw-48
		var lx = r.position.x+24
		var rx = lx+sw+20 if short else lx
		var y = r.position.y+70
		for pair in [["sound","Sound"],["reduced_motion","Reduced motion"],["show_hints","Show hints"]]:
			var key = pair[0]; var caption = pair[1]
			_button("toggle_"+key,caption+"    "+("ON" if settings.values[key] else "OFF"),Rect2(lx,y,sw,44),func(): settings.set_value(key,not settings.values[key]); _apply_preferences(); _rebuild(),settings.values[key])
			y += 50
		if short: y = r.position.y+70
		for pair in [["sfx_volume","SFX"],["announcer_volume","Announcer"]]:
			_volume_slider(pair[0],pair[1],Rect2(rx,y,sw,44)); y += 50
		_button("difficulty","AI: "+str(settings.values.difficulty),Rect2(rx,y,sw,44),func():
			_code_taps += 1
			if _code_taps == 7:
				_code_taps = 0; overlay = "secret_codes"
				_code_message = "Unlock characters and backgrounds for your account. Codes never change match rules."
			else:
				var levels = ["Easy","Medium","Hard"]; settings.set_value("difficulty",levels[(levels.find(settings.values.difficulty)+1)%3])
			_rebuild())
		y += 52
		var name_x = rx+sw+20 if short else rx
		var name_y = r.position.y+70 if short else y
		var name_field = _field("player_name","Screen name",Rect2(name_x,name_y,sw,44),str(settings.values.player_name))
		name_field.max_length = 24
		if not test_online_bypass and account.store.complete():
			var save_width = 60 if short else 120
			name_field.size.x = sw-save_width-8
			_button("save_name","Change",Rect2(name_x+sw-save_width,name_y,save_width,44),func(): account.rename(str(controls.player_name.text)))
			name_field.text_submitted.connect(account.rename)
			var notice = Label.new(); notice.position = Vector2(lx,r.position.y+210) if short else Vector2(rx,y+46); notice.size = Vector2(pw-48,22) if short else Vector2(sw,34)
			notice.text = account.rename_message; notice.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			notice.add_theme_font_override("font",P.SANS); notice.add_theme_font_size_override("font_size",16); notice.add_theme_color_override("font_color",P.PALE)
			add_child(notice); ui_nodes.append(notice); controls["name_status"] = notice
			_settings_name_status()
		else:
			name_field.text_changed.connect(func(value):
				var clean = value.strip_edges().left(24)
				settings.set_value("player_name",clean); profile.data.display_name = clean; profile.save())
		_button("account_email","Account",Rect2(lx,r.end.y-116,sw*.52-4,44),func():
			overlay = "account_options"; _rebuild())
		_button("replay_tutorial","How to play",Rect2(lx+sw*.52+4,r.end.y-116,sw*.48-4,44),func(): start_tutorial(true))
		_button("done","Return",Rect2(lx,r.end.y-62,sw*.48,44),_close_overlay,true)
		_button("cosmetics","Appearance",Rect2(lx+sw*.52,r.end.y-62,sw*.48,44),func(): overlay = "cosmetics"; _rebuild())
		# Round 5a: blocked-player list only when the server advertises chat.
		if social.chat() and not test_online_bypass and account.store.complete():
			_button("blocked_players","Blocked players",Rect2(lx,r.end.y-170,sw,44),open_blocked_players)
		if short:
			controls.account_email.position = Vector2(name_x,r.position.y+120); controls.account_email.size = Vector2(sw,44)
			controls.replay_tutorial.position = Vector2(name_x,r.position.y+170); controls.replay_tutorial.size = Vector2(sw,44)
			controls.done.size.x = (pw-48)*.48
			controls.cosmetics.position.x = lx+(pw-48)*.52; controls.cosmetics.size.x = (pw-48)*.48
			if controls.has("blocked_players"):
				if r.position.y+264 <= r.end.y-62: controls.blocked_players.position = Vector2(name_x,r.position.y+220); controls.blocked_players.size = Vector2(sw,44)
				else:
					controls.account_email.size.x = (sw-8)*.5
					controls.blocked_players.position = Vector2(name_x+(sw+8)*.5,r.position.y+120); controls.blocked_players.size = Vector2((sw-8)*.5,44)
	elif overlay == "account_options":
		var x = r.position.x+24; var y = r.position.y+74; var w = r.size.x-48
		_button("edit_account_email","Account email",Rect2(x,y,w,48),open_account_email)
		if (account.deletion_capable or account.store.data.deletion_uncertain) and account.store.has_device_token():
			_button("delete_account","Delete account",Rect2(x,y+62,w,48),func():
				overlay = "delete_account"; deletion.begin())
		if account.store.data.deletion_uncertain:
			_modal_label("An earlier deletion may have completed. Automatic account creation is blocked.",Rect2(x,y+122,w,90),17,P.PALE)
			_button("resolve_deletion","Sign in to resolve",Rect2(x,y+220,w,48),func():
				recovery.begin(); page = "recovery"; overlay = ""; _rebuild())
			_button("start_fresh","Start fresh on this device",Rect2(x,y+282,w,48),func():
				overlay = "local_reset"; deletion.begin())
		if not account.store.data.deletion_uncertain:
			_modal_label(_account_status_copy(),Rect2(x,y+114,w,54),14,P.PALE)
			_button("sign_out","Sign out",Rect2(x,y+172,w,48),func(): overlay = "signout_confirm"; _rebuild())
		_button("account_options_back","Back",Rect2(x,y+(344 if account.store.data.deletion_uncertain else 226),w,48),func(): overlay = "settings"; _rebuild())
	elif overlay == "signout_confirm":
		var x = r.position.x+24; var w = r.size.x-48
		var scroll = ScrollContainer.new(); scroll.position = Vector2(x,r.position.y+70); scroll.size = Vector2(w,r.size.y-160)
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		add_child(scroll); ui_nodes.append(scroll)
		var copy = Label.new(); copy.text = _signout_copy(); copy.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		copy.size_flags_horizontal = Control.SIZE_EXPAND_FILL; copy.add_theme_font_size_override("font_size",18)
		scroll.add_child(copy); controls["signout_copy"] = copy
		_button("confirm_signout","Sign out",Rect2(x,r.end.y-74,w*.48,48),_confirm_signout)
		_button("cancel_signout","Stay signed in",Rect2(x+w*.52,r.end.y-74,w*.48,48),func(): overlay = "account_options"; _rebuild(),true)
	elif overlay == "secret_codes":
		var x = r.position.x+24; var y = r.position.y+70; var w = r.size.x-48
		var scroll = ScrollContainer.new(); scroll.position = Vector2(x,y); scroll.size = Vector2(w,r.size.y-144)
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		add_child(scroll); ui_nodes.append(scroll)
		var content = Control.new(); content.custom_minimum_size = Vector2(w-16,208); scroll.add_child(content)
		var code = _field("secret_code","Enter code",Rect2(0,0,w-16,48))
		code.reparent(content,false); ui_nodes.erase(code); code.max_length = 32
		var redeem = _button("redeem_code","Checking…" if _code_pending else "Unlock",Rect2(0,58,w-16,44),func():
			_redeem_code(str(controls.secret_code.text)))
		redeem.reparent(content,false); ui_nodes.erase(redeem)
		var status = _modal_label(_code_message,Rect2(0,110,w-16,90),16,P.PALE); status.reparent(content,false); ui_nodes.erase(status)
		_button("codes_back","Settings",Rect2(x,r.end.y-62,w,44),func(): overlay = "settings"; _rebuild())
	elif overlay == "cosmetics":
		var x = r.position.x+24; var y = r.position.y+74; var w = r.size.x-48
		_button("background_theme","Sky: "+Themes.item(settings.values.background_theme,Themes.available(settings.values.unlocked_backgrounds)).name,Rect2(x,y,w,44),func():
			settings.set_value("background_theme",Themes.next(settings.values.background_theme,Themes.available(settings.values.unlocked_backgrounds))); _apply_preferences(); _rebuild())
		_button("board_theme","Board: "+Themes.item(settings.values.board_theme,Themes.BOARDS).name,Rect2(x,y+50,w,44),func():
			settings.set_value("board_theme",Themes.next(settings.values.board_theme,Themes.BOARDS)); _apply_preferences(); _rebuild())
		_button("classic","Restore crystal",Rect2(x,y+100,w,44),func():
			settings.set_value("background_theme","crystal"); settings.set_value("board_theme","crystal"); _apply_preferences(); _rebuild())
		_button("profile_hero","Hero: "+Roster.get_hero(str(profile.data.character_id)).name,Rect2(x,y+150,w,44),func(): _pending_game = {}; _select_player = 0; open_character_select())
		_button("done","Settings",Rect2(x,r.end.y-62,w,44),func(): overlay = "settings"; _rebuild(),true)

	elif overlay == "how":
		_button("done","I’m ready",Rect2(r.position.x+24,r.end.y-70,pw-48,48),_close_overlay,true)
	elif overlay in ["leave_confirm","online_end"]:
		var body = Clock.leave_copy(leave_costs_loss()) if overlay == "leave_confirm" else end_message
		var label = _modal_label(body,Rect2(r.position.x+24,r.position.y+72,pw-48,r.size.y-200),20,P.PALE)
		label.name = "ModalCopy"; controls["modal_copy"] = label
		var half = (pw-60)*.5; var y = r.end.y-70
		if overlay == "leave_confirm":
			_button("leave_match","Leave match",Rect2(r.position.x+24,y,half,52),go_home)
			_button("stay","Stay",Rect2(r.position.x+36+half,y,half,52),_close_overlay,true)
			if leave_costs_loss() == false and transport is HTTP and transport.online2:
				_modal_label("First moves — no-shows cancel with no loss",Rect2(r.position.x+24,y-34,pw-48,26),14,P.MUTED)
		else:
			_button("end_lobby","Online lobby",Rect2(r.position.x+24,y,half,52),request_online,true)
			_button("end_menu","Main menu",Rect2(r.position.x+36+half,y,half,52),go_home)
	elif overlay == "blocked":
		var scroll = ScrollContainer.new(); scroll.position = r.position+Vector2(24,76); scroll.size = Vector2(pw-48,r.size.y-76-128)
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED; add_child(scroll); ui_nodes.append(scroll)
		var rows = VBoxContainer.new(); rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL; rows.add_theme_constant_override("separation",6); scroll.add_child(rows)
		for blocked_name in social.blocks:
			var row = HBoxContainer.new(); row.add_theme_constant_override("separation",8); rows.add_child(row)
			var label = Label.new(); label.text = blocked_name; label.size_flags_horizontal = Control.SIZE_EXPAND_FILL; label.clip_text = true
			label.add_theme_font_override("font",P.SANS); label.add_theme_font_size_override("font_size",20); label.add_theme_color_override("font_color",P.WHITE)
			row.add_child(label)
			var unblock = OrnateButton.new(); unblock.name = "unblock_"+blocked_name; unblock.caption = "Unblock"; unblock.custom_minimum_size = Vector2(112,44)
			unblock.pressed.connect(func(): sound.cue("ui"); blocked_status = "Unblocking…" if social.unblock(blocked_name) else "Couldn't unblock right now."; _rebuild())
			row.add_child(unblock); controls[unblock.name] = unblock
		if social.blocks.is_empty() and blocked_status.is_empty(): blocked_status = "No blocked players."
		controls["blocked_status"] = _modal_label(blocked_status,Rect2(r.position.x+24,r.end.y-122,pw-48,48),16,P.GOLD)
		_button("done","Settings",Rect2(r.position.x+24,r.end.y-66,pw-48,48),func(): overlay = "settings"; _rebuild(),true)
	elif overlay == "result":
		_button("again","Play Again",Rect2(r.position.x+26,r.end.y-122,pw-52,50),rematch,true)
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
	var tw = P.DISPLAY.get_string_size("LEXERLY",HORIZONTAL_ALIGNMENT_LEFT,-1,int(fs)).x
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
	var turn_r: Rect2 = layout.turn
	if layout.mode == "phone_portrait":
		turn_r.position.x = match_sound_rect().end.x+6
		var right = chat_button_rect().position.x if mode == "online" and chat_capable() else layout.header.end.x-header_button_size()
		turn_r.size.x = maxf(1,right-6-turn_r.position.x)
	_draw_turn(turn_r,u)
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
	else:
		var lines = online_lines()
		var joined_line = "   ·   ".join(lines.filter(func(v): return not v.is_empty()))
		if not joined_line.is_empty(): P.text(self,fit_label(joined_line,layout.message.size.x,13),layout.message,13,_online_line_color())
	if hint_busy: P.text(self,"Reading the threads…",Rect2(layout.board.position.x,layout.board.end.y-22,layout.board.size.x,20),14,P.PALE)
## Round 3e phone portrait has no info panel: one slim lane under the board carries
## messages, "Reading the threads…", the result, else a quiet "Play X in Center" hint.
func _draw_phone_lane(r: Rect2):
	var fs = int(minf(13,r.size.y-2))
	var lines = online_lines()
	if not lines[1].is_empty(): P.text(self,fit_label(lines[1],r.size.x,11),Rect2(r.position.x,r.end.y+1,r.size.x,14),11,P.GOLD if not idle_turn_warning().is_empty() else Color(P.MUTED,.85))
	if not message.is_empty(): P.text(self,fit_label(message,r.size.x,fs),r,fs,P.GOLD)
	elif not lines[0].is_empty(): P.text(self,fit_label(lines[0],r.size.x,fs),r,fs,_online_line_color())
	elif hint_busy: P.text(self,"Reading the threads…",r,fs,P.PALE)
	elif game.status != 0: P.text(self,result_line(),r,fs,P.mark_color(game.status) if game.status != 3 else P.MUTED)
	else:
		var where = "any open board" if game.active_board == -1 else Rules.BOARD_NAMES[game.active_board]
		P.text(self,"Play "+("X" if game.turn == 1 else "O")+" in "+where,r,fs,Color(P.MUTED,.9))
func _online_line_color() -> Color:
	if not transport is HTTP or transport.reconnecting or transport.room.get("opponent_connected") == false: return P.GOLD
	var info = turn_info()
	return Clock.tier_color(info.tier) if info.phase in ["turn","still_there"] and info.tier != "calm" else P.PALE
func _draw_turn(r: Rect2, u: float):
	P.panel(self,r,false,1,r.size.y >= 34)
	var fs = int(clampf(r.size.y*.56,15,28)*minf(u,1.2))
	var icon_r = fs*.62
	var caption = "Turn:"
	var mark = game.turn
	if game.status == 3: caption = "Draw"; mark = 0
	elif game.status != 0: caption = "wins"; mark = game.status
	elif mode == "online":
		caption = online_turn_caption()
		if r.size.x < 130:
			if caption == "Opponent's turn": caption = "Their turn"
			elif caption == "Waiting for opponent": caption = "Waiting…"
			elif caption == "Sending move…": caption = "Sending…"
			elif caption == "Reconnecting…": caption = "Syncing…"
			elif caption == "Checking result…": caption = "Checking…"
		while fs > 10 and P.text_width(caption,fs,P.SERIF)+fs*.62*2.6 > r.size.x-16: fs -= 1
		icon_r = fs*.62
	var tw = P.text_width(caption,fs,P.SERIF)
	var total = tw+(icon_r*2.6 if mark != 0 else 0)
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
		elif game.status == 0 and (mode != "online" or local_online_turn()) and (game.active_board == -1 or game.active_board == b): states.append("active")
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
	var heading = {"settings":"SETTINGS","account_options":"ACCOUNT","signout_confirm":"SIGN OUT?","setup":"CHOOSE YOUR PATH","how":"HOW TO PLAY","cosmetics":"APPEARANCE","secret_codes":"SECRET CODES","leave_confirm":"LEAVE MATCH?","blocked":"BLOCKED PLAYERS"}.get(overlay,"")
	if overlay == "online_end": heading = Clock.cancelled_title(str(transport.room.get("end_reason","")) if transport is HTTP else "")
	P.text(node,heading,Rect2(r.position+Vector2(20,23),Vector2(r.size.x-72,44)),25,P.PALE,P.SERIF,HORIZONTAL_ALIGNMENT_CENTER,.6)
	if overlay == "setup":
		if not short: P.text(node,"Choose difficulty, then your sigil",Rect2(r.position+Vector2(20,65),Vector2(r.size.x-40,25)),17,P.MUTED)
		if not short: P.text(node,"X always weaves the first thread.",Rect2(r.position.x+20,r.end.y-48,r.size.x-40,24),16,P.GOLD)
	elif overlay == "settings":
		pass # The Account and tutorial row occupies this lane.
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
	if _require_screen_name(): return false
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

## Web QA hook: ?nw_scenario=versus|winner|winner_cpu|tutorial_auto&nw_hero=shard_jack&nw_rival=max_granite
## Starts a live clip (no analytic seek) so a browser can verify playback. No-ops without params.
## On web the clips are downloaded first; this hook may wait for them (QA only, never used in play).
func _clip_preview():
	# URL/environment QA parameters cannot opt a real incomplete account out.
	# Capture scripts must explicitly set test_online_bypass or debug_scenario.
	if _require_screen_name(): return
	var scenario = OS.get_environment("NW_SCENARIO") if OS.has_environment("NW_SCENARIO") else ""
	var hero = OS.get_environment("NW_HERO") if OS.has_environment("NW_HERO") else ""
	var rival = OS.get_environment("NW_RIVAL") if OS.has_environment("NW_RIVAL") else ""
	if OS.has_feature("web"):
		var qs_scenario = str(JavaScriptBridge.eval("(new URLSearchParams(window.location.search)).get('nw_scenario')||''"))
		var qs_hero = str(JavaScriptBridge.eval("(new URLSearchParams(window.location.search)).get('nw_hero')||''"))
		var qs_rival = str(JavaScriptBridge.eval("(new URLSearchParams(window.location.search)).get('nw_rival')||''"))
		if not qs_scenario.is_empty() and qs_scenario != "null": scenario = qs_scenario
		if not qs_hero.is_empty() and qs_hero != "null": hero = qs_hero
		if not qs_rival.is_empty() and qs_rival != "null": rival = qs_rival
	if scenario.is_empty() or scenario == "null": return
	if hero.is_empty() or hero == "null": hero = "shard_jack"
	if rival.is_empty() or rival == "null": rival = "max_granite"
	if not Roster.valid(hero): hero = "shard_jack"
	hero = Roster.canonical_id(hero)
	if not Roster.valid(rival) or Roster.canonical_id(rival) == hero:
		rival = "max_granite" if hero != "max_granite" else "shard_jack"
	rival = Roster.canonical_id(rival)
	profile.data.onboarded = true
	profile.data.character_id = hero
	profile.data.display_name = "Patrick"
	settings.values.player_name = "Patrick"
	settings.values.reduced_motion = false
	rival_character = rival
	if scenario == "tutorial_auto":
		# Needs an already-complete local account (URL cannot skip first-run name).
		# Do not set test_online_bypass: that would suppress the first-play tutorial.
		account.store.data.tutorial_completed = false
		_tutorial_on_home()
		return
	test_online_bypass = true
	hero_video.prefetch_pair(hero, rival)
	var needed: Array = []
	if scenario == "versus":
		if hero_video.has_clip(hero,"intro"): needed.append([hero,"intro"])
		if hero_video.has_clip(rival,"intro"): needed.append([rival,"intro"])
	elif scenario in ["winner","winner_cpu"]:
		var winner_id = rival if scenario == "winner_cpu" else hero
		if hero_video.has_clip(winner_id,"victory"): needed.append([winner_id,"victory"])
	var deadline = Time.get_ticks_msec() + 20000
	while Time.get_ticks_msec() < deadline and not needed.is_empty():
		var ready = true
		for item in needed:
			if not hero_video.is_ready(item[0],item[1]): ready = false; break
		if ready: break
		await get_tree().process_frame
	if scenario == "versus":
		start_game("computer",1,true,true); return
	if scenario in ["winner","winner_cpu"]:
		# Do not use debug_load_position: that is debug-build only and would no-op in a release web export.
		human_mark = 1; mode = "computer"; page = "game"; overlay = ""; _debug_capture = false
		var result_mark = 2 if scenario == "winner_cpu" else 1
		var patterns: Array = []
		for i in range(9): patterns.append(".........")
		patterns[0] = "OOOXX...." if result_mark == 2 else "XXXOO...."
		patterns[1] = patterns[0]
		patterns[2] = "OO.XX...." if result_mark == 2 else "XX.OO...."
		var staged = Rules.new(); staged.deserialize({"v":1,"cells":"".join(patterns),"turn":result_mark,"active":2,"history":[]})
		game.deserialize(staged.serialize()); board.clear_effects(); _result_shown = false; _spotlight_done = false
		game.play(2,2)
		_refresh_labels(); _rebuild(); _show_spotlight()

func debug_scenario(scenario: String, progress: float = .45):
	if not OS.is_debug_build(): return
	_debug_capture = true; clock = 4; backdrop.clock = 4; P.clock = 4
	if scenario in ["tutorial","tutorial_claim","tutorial_win"]:
		start_game("local"); start_tutorial(true)
		var target = 3 if scenario == "tutorial_claim" else (4 if scenario == "tutorial_win" else 1)
		for i in range(target): tutorial.next_step()
		tutorial.age = 1; tutorial.set_process(false); tutorial.queue_redraw(); return
	if scenario in ["email","account_email","email_code"]:
		if scenario == "account_email": page = "title"; overlay = "account"
		else: page = "email"; overlay = ""
		_email_draft = "" if scenario == "email" else "weaver@example.com"
		message = ""
		if scenario == "email_code":
			var now = int(Time.get_unix_time_from_system())
			account.store.data.email = "weaver@example.com"
			account.store.data.email_status = "not_verified"
			account.email_pending = true
			account.email_challenge = {
				"challenge_id":"ec_capture",
				"resend_available_at":Time.get_datetime_string_from_unix_time(now+83)+".000Z",
				"expires_at":Time.get_datetime_string_from_unix_time(now+601)+".000Z",
				"email":"weaver@example.com"
			}
			_email_code_draft = ""
		_rebuild(); return
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
		_refresh_labels(); _show_spotlight(); cinematic.seek(progress*5)
		cinematic.frozen = true; cinematic.pose(); _result_shown = true
		overlay = "result" if cinematic.buttons_shown else ""; _rebuild()
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
		_show_spotlight(); cinematic.seek(0); cinematic.seek(progress*cinematic.duration())
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

func _result_chat():
	if mode != "online" or not chat_capable(): return
	_chat_button(chat_button_rect(),31)
	if chat_open: _build_chat_panel(ChatPanel.panel_rect(layout),41)
func _winner_controls(s: Vector2):
	var g = cinematic.result_geometry(s) if cinematic.combined_result else Cinematic.card_geometry(s,"draw" if game.status == 3 else "spotlight")
	for item in [["again","REMATCH",g.again,rematch,true],["menu","MAIN MENU",g.menu,go_home,false]]:
		if item[0] == "again" and online_tournament.match_active:
			item[1] = "VIEW BRACKET"; item[3] = online_tournament.return_to_bracket
		if item[0] == "again" and tournament.match_active:
			item[1] = "REPLAY MATCH" if game.status == 3 else ("THE CROWN" if tournament.session.active.get("status","") == "champion" else "VIEW BRACKET")
			item[3] = tournament.after_match
		var button = preload("res://characters/match_button.gd").new()
		button.caption = item[1]; button.position = item[2].position; button.size = item[2].size; button.accent = item[4]
		button.z_index = 31; button.pressed.connect(item[3]); button.pressed.connect(func(): sound.cue("ui"))
		add_child(button); ui_nodes.append(button); controls[item[0]] = button
	_apply_result_anim()
	if mode == "online" and is_instance_valid(transport) and not online_tournament.match_active:
		controls.again.disabled = transport.local_rematch or not remote_ready
		controls.again.caption = "ACCEPT" if transport.remote_rematch and not transport.local_rematch else "REMATCH"
		var label = Label.new(); label.z_index = 31; label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		label.text = (transport.rematch_status() if cinematic.combined_result else message) if not message.is_empty() else transport.rematch_status(); label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.position = Vector2(g.again.position.x,g.again.position.y-34) if cinematic.combined_result else Vector2(s.x*.04,g.again.position.y-38)
		label.size = Vector2(g.menu.end.x-g.again.position.x if s.y < 500 else g.again.size.x,30) if cinematic.combined_result else Vector2(s.x*.92,32)
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

func _redeem_code(raw: String):
	if _code_pending: return
	if not account.store.online_ready():
		_code_message = "Sign in and connect to the account server to unlock a code."; _rebuild(); return
	_code_pending = true; _code_owner = str(account.store.data.device_token)
	_code_message = "Checking code…"
	account.api.submit("/me/unlocks",HTTPClient.METHOD_POST,{"code":raw.strip_edges()},"cosmetic_unlock",_code_owner)
	_rebuild()
func _code_completed(operation: String, response: int, data: Dictionary, problem: String):
	if operation != "cosmetic_unlock" or not _code_pending: return
	_code_pending = false
	if _code_owner != str(account.store.data.device_token) or not account.store.online_ready(): return
	_code_owner = ""
	if not problem.is_empty() or response < 200 or response >= 300:
		_code_message = problem if not problem.is_empty() else "Unable to unlock. Please try again."
	else:
		settings.values.unlocked_heroes = data.get("unlocked_heroes",[]) if data.get("unlocked_heroes") is Array else []
		var unlocked = data.get("unlocked_backgrounds",[])
		settings.values.unlocked_backgrounds = unlocked if unlocked is Array else []
		var grant = data.get("unlock",{})
		var selected = str(grant.get("id","")) if grant is Dictionary and grant.get("kind") == "background" else ""
		if Themes.valid(selected,Themes.available(settings.values.unlocked_backgrounds)):
			settings.set_value("background_theme",selected)
			_code_message = "Unlocked! Choose your background anytime in Appearance."
		elif grant is Dictionary and grant.get("kind") == "hero" and Roster.selectable(str(grant.get("id","")),settings.values.unlocked_heroes):
			_code_message = "Unlocked! %s is now available in character selection." % Roster.get_hero(str(grant.id)).name
		else: _code_message = "Your account unlocks have been refreshed."
		_apply_preferences()
	if overlay == "secret_codes": _rebuild()
