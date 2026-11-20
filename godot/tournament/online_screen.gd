extends "res://ui/online_screen.gd"
## Tournament chooser/lobby/waiting room, sharing the normal online visual language.
const View = preload("res://tournament/bracket_view.gd")
const Model = preload("res://tournament/online_model.gd")
const Contrast = preload("res://ui/readability.gd")
var flow
var bracket
var clock_label: Label
var roster_label: Label
var roster_scroll: ScrollContainer
var ready_button
var leave_dialog: ConfirmationDialog
var model: Dictionary = {}
var _body: Control
var _scroll: ScrollContainer
var _form_width: float
var _capacity_label: Label
var _listing_root: Control
var _listing_note: Label
var _listed_codes: Array[String] = []
var _last_listing: Array = []
var _listing_initialized := false
class TournamentCard extends Button:
	var heading: String
	var helper: String
	var glyph: String
	func _ready():
		for item in ["normal","hover","pressed","disabled","focus"]: add_theme_stylebox_override(item,StyleBoxEmpty.new())
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		mouse_entered.connect(queue_redraw); mouse_exited.connect(queue_redraw)
		focus_entered.connect(queue_redraw); focus_exited.connect(queue_redraw)
	func _draw():
		var rect := Rect2(Vector2(3,3),size-Vector2(6,6))
		P.panel(self,rect,is_hovered() or has_focus(),1.0,true)
		var band := minf(34.0,size.y*.28)
		P.text(self,glyph,Rect2(12,10,size.x-24,band),22,P.MUTED,P.SERIF)
		P.text(self,heading,Rect2(12,band+10,size.x-24,size.y*.32),P.fit_size(heading,size.x-30,27,P.SERIF),P.PALE,P.SERIF)
		P.text(self,helper,Rect2(12,size.y*.69,size.x-24,size.y*.19),P.fit_size(helper,size.x-30,16),P.GOLD,P.SANS)

func _ready():
	screen = flow.state
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_header("TOURNAMENT" if screen == "chooser" else "ONLINE TOURNAMENTS","back")
	if screen == "chooser": _chooser()
	elif screen == "waiting": _waiting_room()
	elif flow.unavailable: _coming_soon()
	else: _online_lobby()
func _header(title: String, back_kind: String = "home"):
	_button("back","Menu" if back_kind == "home" else "Back",Rect2(16,12,100,44),back_kind)
	var w := size.x-44
	controls["tournament_header"] = _label(title,Rect2(22,62,w,34),P.fit_size(title,w,25,P.SERIF),P.PALE,true)
func _chooser():
	var w = minf(460,size.x-40); var x = (size.x-w)*.5
	var y = maxf(110,size.y*.25)
	if size.y < 500:
		_label("CHOOSE YOUR RIVALS",Rect2(x,110,w,36),26,P.GOLD,true)
		_button("computer","Vs Computer",Rect2(x,164,(w-12)*.5,54),"computer","",true)
		_button("online_tournament","Online",Rect2(x+(w+12)*.5,164,(w-12)*.5,54),"online")
		_label("Computer: 8 heroes. Online: 3–8 players.",Rect2(x,234,w,54),19); return
	_label("CHOOSE YOUR RIVALS",Rect2(x,y,w,36),26,P.GOLD,true)
	_label("One bracket. One champion.",Rect2(x,y+42,w,34),20)
	_button("computer","Vs Computer",Rect2(x,y+96,w,54),"computer","",true)
	_button("online_tournament","Online",Rect2(x,y+164,w,54),"online")
	_label("Computer: 8 heroes, rising difficulty.\nOnline: 3–8 players, live scores and byes.",Rect2(x,y+230,w,66),18,P.PALE)
func _coming_soon():
	var w = minf(500,size.x-40); var x = (size.x-w)*.5; var y = maxf(112,size.y*.25)
	_label(flow.COMING_SOON,Rect2(x,y,w,76),28,P.GOLD,true)
	_label("The arena is getting ready for online brackets. You can play a tournament against the computer today.",Rect2(x,y+84,w,94),20)
	_button("computer","Vs Computer",Rect2(x,y+194,w,54),"computer","",true)
func _picker(id: String, label_value: String, values: Array, current: int, rect: Rect2):
	_label(label_value,Rect2(rect.position,Vector2(rect.size.x*.44,rect.size.y)),18,P.GOLD)
	var picker = OptionButton.new(); picker.position = rect.position+Vector2(rect.size.x*.46,0); picker.size = Vector2(rect.size.x*.54,rect.size.y)
	picker.add_theme_font_override("font",P.SANS); picker.add_theme_font_size_override("font_size",20)
	for value in values:
		picker.add_item(str(value)+(" min" if id == "start" else " players"),int(value))
		if int(value) == current: picker.select(picker.item_count-1)
	picker.item_selected.connect(func(i): action.emit(id,str(picker.get_item_id(i))))
	add_child(picker); controls[id] = picker
func _online_lobby():
	var before = get_children()
	_form_width = minf(750 if flow.lobby_view == "hub" else 560,size.x-44)
	_scroll = ScrollContainer.new()
	_scroll.position = Vector2((size.x-_form_width-12)*.5,105)
	_scroll.size = Vector2(_form_width+12,maxf(84,size.y-181))
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(_scroll)
	_body = Control.new()
	_body.custom_minimum_size.x = _form_width
	_scroll.add_child(_body)
	match flow.lobby_view:
		"create": _build_create()
		"join": _build_join()
		_: _build_hub()
	for child in get_children():
		if child not in before and child != _scroll: child.reparent(_body,false)
	_status(Rect2((size.x-_form_width)*.5,size.y-72,_form_width,62)); status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	update_state()
func _hub_card(id: String, heading: String, helper: String, glyph: String, area: Rect2):
	var card := TournamentCard.new()
	card.name = id; card.tooltip_text = helper; card.accessibility_name = heading; card.heading = heading; card.helper = helper; card.glyph = glyph
	card.position = area.position; card.size = area.size
	card.pressed.connect(func(): action.emit(id,"")); add_child(card); controls[id] = card
func _build_hub():
	var w := _form_width
	var wide := w >= 610
	var h := 106.0 if size.y < 525 else (109.0 if size.x < 400 else 138.0)
	var body_height := (h if wide else h*2+13)+140
	var y := maxf(4,(_scroll.size.y-body_height)*.34)
	var title := "THE TOURNAMENT ARENA"
	controls["arena_heading"] = _center_label(title,Rect2(0,y,w,36),P.fit_size(title,w,25,P.SERIF),P.GOLD,true)
	_center_label("One bracket. One champion.",Rect2(0,y+40,w,34),18,P.PALE)
	y += 85
	var half := (w-18)*.5
	_hub_card("show_create","Create Tournament","Host a new bracket","✦",Rect2(0,y,half if wide else w,h))
	_hub_card("show_join","Join Tournament","Browse public games or enter a code","◈",Rect2(half+18 if wide else 0,y if wide else y+h+13,half if wide else w,h))
	y += (h if wide else h*2+13)+18
	var account_width := minf(w,250)
	_button("account","Your Screen Name & Hero",Rect2((w-account_width)*.5,y,account_width,44),"account")
	_body.custom_minimum_size.y = y+52
func _label(value: String, rect: Rect2, font_size: int = 18, color: Color = P.WHITE, serif: bool = false) -> Label:
	# Enable wrapping before assigning width; an unwrapped Label otherwise
	# clamps its initial size to the whole sentence and keeps that size.
	var label := Label.new()
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_override("font",P.SERIF if serif else P.SANS)
	label.add_theme_font_size_override("font_size",font_size)
	label.add_theme_color_override("font_color",color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.text = value
	label.position = rect.position
	label.size = rect.size
	add_child(label)
	return label
func _center_label(value: String, rect: Rect2, font_size: int, color: Color, serif: bool = false) -> Label:
	var label := _label(value,rect,font_size,color,serif)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return label
func _build_create():
	var w := _form_width
	_center_label("Create Tournament",Rect2(6,7,w-12,42),27,P.PALE,true)
	_picker("players","Group size",[3,4,5,6,7,8],flow.desired_players,Rect2(8,56,w-16,48))
	_capacity_label = _label("",Rect2(10,112,w-20,48),15,P.MUTED)
	var options: Array = flow.capabilities.get("tournament_start_options",[2,5,10,15,30,60])
	_picker("start","Starts in",options,flow.starts_in_minutes,Rect2(8,166,w-16,48))
	_button("privacy","",Rect2(8,226,w-16,46),"privacy")
	_field("password","Tournament password",flow.password,Rect2(8,282,w-16,46),true)
	controls["create_rules"] = _label("A full bracket starts in 10 seconds. A scheduled start with fewer than 3 players is cancelled.",Rect2(10,0,w-20,58),15,P.PALE)
	_button("create_tournament","Create Tournament",Rect2(8,0,w-16,52),"create","",true)
func _build_join():
	var w := _form_width
	_center_label("Join Tournament",Rect2(6,7,w-12,42),27,P.PALE,true)
	_label("JOIN BY CODE",Rect2(10,57,w-20,24),15,P.GOLD)
	var code_field = _field("room_code","Code starting with T","",Rect2(8,85,w-16,46))
	code_field.max_length = 6
	code_field.text = flow.join_code
	code_field.text_submitted.connect(func(_value): action.emit("join",""))
	_button("join_private","",Rect2(8,139,w-16,44),"join_private")
	_field("join_password","Tournament password",flow.join_password,Rect2(8,192,w-16,46),true)
	_button("join_tournament","Join by Code",Rect2(8,0,w-16,49),"join","",true)
	controls["public_title"] = _label("PUBLIC TOURNAMENTS",Rect2(10,0,w-116,48),16,P.GOLD)
	_button("refresh","Refresh",Rect2(w-101,0,93,44),"refresh")
	_listing_root = Control.new(); _listing_root.mouse_filter = Control.MOUSE_FILTER_IGNORE; _body.add_child(_listing_root)
	_listing_note = _label("",Rect2(10,0,w-20,48),16,P.MUTED)
	_listing_note.reparent(_listing_root,false)
func _sync_create():
	if not controls.has("create_tournament"): return
	_capacity_label.text = "%d seats; at least 3 players. Byes advance automatically." % flow.capacity(flow.desired_players)
	var secret: LineEdit = controls.password
	secret.visible = flow.private_tournament
	controls.privacy.caption = "Private · Password required" if flow.private_tournament else "Public · Listed in the arena"
	var y := 337.0 if flow.private_tournament else 282.0
	var rules: Label = controls.create_rules
	rules.position.y = y
	var rules_height := maxf(58,rules.size.y)
	controls.create_tournament.position.y = y+rules_height+12
	controls.create_tournament.disabled = flow.action_busy()
	_body.custom_minimum_size.y = y+rules_height+75
func _sync_join():
	if not controls.has("join_tournament"): return
	var secret: LineEdit = controls.join_password
	secret.visible = flow.join_with_password
	controls.join_private.caption = "Private password: on" if flow.join_with_password else "Private tournament?"
	var y := 249.0 if flow.join_with_password else 191.0
	controls.join_tournament.position.y = y
	controls.join_tournament.disabled = flow.action_busy()
	controls.public_title.position.y = y+64
	controls.refresh.position.y = y+66
	controls.refresh.disabled = flow.list_busy()
	_listing_root.position.y = y+119
	_sync_public_entries()
	var note: String = flow.list_problem
	if note.is_empty() and flow.listing.is_empty():
		note = "Checking public tournaments…" if flow.list_busy() else "No public tournaments yet."
	_listing_note.text = note
	_listing_note.visible = not note.is_empty()
	var offset := 48.0 if _listing_note.visible else 0.0
	for i in range(_listed_codes.size()):
		var button = controls.get("join_"+_listed_codes[i])
		if is_instance_valid(button):
			button.position.y = offset+i*58
			button.disabled = flow.action_busy()
	_body.custom_minimum_size.y = _listing_root.position.y+offset+_listed_codes.size()*58+12
func _sync_public_entries():
	if _listing_initialized and _last_listing == flow.listing: return
	_listing_initialized = true
	_last_listing = flow.listing.duplicate(true)
	for code in _listed_codes:
		var key := "join_"+code
		var child = controls.get(key)
		if is_instance_valid(child):
			_listing_root.remove_child(child)
			child.queue_free()
		controls.erase(key)
		if flow.screen == self: flow.main.controls.erase(key)
	_listed_codes.clear()
	for entry in flow.listing:
		if not entry is Dictionary: continue
		var code := str(entry.get("code",""))
		if code.length() != 6 or code in _listed_codes: continue
		_listed_codes.append(code)
		var host := str(entry.get("host","Player")).replace("\n"," ").replace("\r"," ").strip_edges()
		if host.is_empty(): host = "Player"
		var detail := " · %d/%d · %s" % [int(entry.get("joined",0)),int(entry.get("size",8)),code]
		if P.SANS.get_string_size(host+detail,HORIZONTAL_ALIGNMENT_LEFT,-1,17).x > _form_width-58:
			while host.length() > 1 and P.SANS.get_string_size(host+"…"+detail,HORIZONTAL_ALIGNMENT_LEFT,-1,17).x > _form_width-58: host = host.left(-1)
			host += "…"
		var caption := host+detail
		var key := "join_"+code
		var btn = _button(key,caption,Rect2(8,0,_form_width-16,52),"join",code)
		btn.font_size = 17
		btn.tooltip_text = str(entry.get("host","Player"))
		btn.reparent(_listing_root,false)
		if flow.screen == self: flow.main.controls[key] = btn
func _waiting_room():
	var data = flow.snapshot
	_label("CODE  "+flow.code,Rect2(22,100,size.x-180,30),24,P.GOLD,true)
	_button("copy","Copy Code",Rect2(size.x-142,100,120,44),"copy")
	clock_label = _label("",Rect2(22,146,size.x-44,58),19,P.PALE)
	var br = Rect2(20,226,size.x-40,maxf(160,size.y-362))
	if size.y >= 500: _label("Cyan: playing · Gold: ready · Scores: boards won",Rect2(20,204,size.x-40,20),13,P.GOLD)
	bracket = View.new(); bracket.position = br.position; bracket.size = br.size; bracket.reduced_motion = reduced_motion; add_child(bracket)
	roster_scroll = ScrollContainer.new(); roster_scroll.position = br.position; roster_scroll.size = br.size
	roster_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED; add_child(roster_scroll)
	roster_label = _label("",Rect2(Vector2.ZERO,br.size),20,P.WHITE)
	roster_label.reparent(roster_scroll,false); roster_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if size.y < 500:
		var x = size.x*.65+8; var w = size.x-x-16
		bracket.position = Vector2(16,110); bracket.size = Vector2(size.x*.65-32,size.y-126)
		roster_scroll.position = bracket.position; roster_scroll.size = bracket.size
		controls.copy.position = Vector2(x,134); controls.copy.size = Vector2(w,44)
		clock_label.position = Vector2(x,184); clock_label.size = Vector2(w,maxf(60,size.y-320))
		for child in get_children():
			if child is Label and child.text.begins_with("CODE  "): child.position = Vector2(x,100); child.size.x = w
	ready_button = _button("ready","Ready · Join Next Match",Rect2(20,size.y-126,size.x-40,48),"ready","",true)
	_button("leave_tournament","Leave Tournament",Rect2(20,size.y-68,size.x-40,48),"confirm_leave")
	if size.y < 500:
		var x = size.x*.65+8; var w = size.x-x-16
		ready_button.position.x = x; ready_button.size.x = w
		controls.leave_tournament.position.x = x; controls.leave_tournament.size.x = w
	# A running tournament leave forfeits the current/next match; pre-start is free.
	action.connect(func(kind,_value):
		if kind != "confirm_leave": return
		if str(flow.snapshot.get("status","")) == "running": _confirm_leave()
		elif str(flow.snapshot.get("status","")) in ["finished","cancelled"]:
			flow.code = ""; flow.snapshot = {}; flow.close()
		else: flow.leave())
	update_state()
func _confirm_leave():
	if is_instance_valid(leave_dialog): return
	leave_dialog = ConfirmationDialog.new(); leave_dialog.title = "Leave tournament?"
	leave_dialog.dialog_text = "Leaving now forfeits your current or next match."
	leave_dialog.ok_button_text = "Leave Tournament"; leave_dialog.cancel_button_text = "Keep Playing"
	leave_dialog.confirmed.connect(flow.leave); leave_dialog.canceled.connect(func(): leave_dialog.queue_free(); leave_dialog = null)
	add_child(leave_dialog); leave_dialog.popup_centered(Vector2i(mini(340,int(size.x)-32),180))
func update_state():
	if screen != flow.state or (flow.unavailable and screen == "lobby"):
		flow.main._rebuild(); return
	if screen == "lobby":
		# Polls update rows and labels only. Keep active fields, caret and scroll alive.
		_sync_create(); _sync_join()
		set_status(flow.status)
		for key in ["show_create","show_join"]:
			if controls.has(key): controls[key].disabled = flow._inflight == "capabilities"
		return
	if screen != "waiting": return
	var next = Model.from_envelope(flow.snapshot)
	var events = Model.result_events(model,next)
	var changed = next != model
	if changed:
		if not events.is_empty() or model.is_empty(): bracket.present(next,events,next.focus_id)
		else:
			bracket.model = next.duplicate(true); bracket.focus_id = next.focus_id
			var current = preload("res://tournament/bracket.gd").next_match(next,next.focus_id)
			bracket.current_id = str(current.match.id) if not current.is_empty() else ""
			bracket._layout()
		model = next
	var has_bracket = not model.rounds.is_empty()
	bracket.visible = has_bracket; roster_scroll.visible = not has_bracket
	if not has_bracket:
		var lines = "REGISTERED HEROES\n\n"
		for p in flow.snapshot.get("players",[]): lines += str(p.get("name","Player"))+" · "+Roster.get_hero(str(p.get("hero",""))).name+"\n"
		roster_label.text = lines
	tick()
func tick():
	if screen != "waiting" or not is_instance_valid(clock_label): return
	clock_label.text = flow.waiting_text()+("\n"+flow.status if not flow.status.is_empty() and flow.snapshot.get("status") != "cancelled" else "")
	ready_button.visible = flow.countdown >= 0
	controls.leave_tournament.caption = "Main Menu" if flow.snapshot.get("status") in ["finished","cancelled"] else "Leave Tournament"
func _draw():
	Contrast.draw_panel(self,Rect2(0,58,size.x,size.y-58))
	if screen == "lobby" and not flow.unavailable:
		var center := Vector2(size.x*.5,size.y*.48)
		for index in range(3):
			draw_arc(center,minf(size.x,size.y)*(.31+index*.13),0,TAU,80,Color(P.GOLD,.073),1,true)
		for i in range(12):
			var at := Vector2(fposmod(41+i*91.7,size.x),106+fposmod(37+i*137.6,maxf(1,size.y-186)))
			P.diamond(self,at,1.6,Color(P.GOLD,.18))
