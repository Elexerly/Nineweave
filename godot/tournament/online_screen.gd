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
func _ready():
	screen = flow.state
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_header("TOURNAMENT" if screen == "chooser" else "ONLINE TOURNAMENTS","back")
	if screen == "chooser": _chooser()
	elif screen == "waiting": _waiting_room()
	elif flow.unavailable: _coming_soon()
	else: _online_lobby()
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
	# The whole form scrolls on phones/short windows; every action remains reachable.
	var before = get_children()
	var wide = size.x >= 900
	var w = minf(460,(size.x-72)*.5) if wide else size.x-48
	var x = 8.0; var y = 0.0
	_label("CREATE A TOURNAMENT",Rect2(x,y,w,34),24,P.GOLD,true)
	y += 42
	_picker("players","Group size",[3,4,5,6,7,8],flow.desired_players,Rect2(x,y,w,48)); y += 56
	var cap = flow.capacity(flow.desired_players)
	_label("%d seats · Starts with everyone who joins (minimum 3). Byes advance automatically." % cap,Rect2(x,y,w,70),18); y += 78
	var options: Array = flow.capabilities.get("tournament_start_options",[2,5,10,15,30,60])
	_picker("start","Starts in",options,flow.starts_in_minutes,Rect2(x,y,w,48)); y += 56
	_button("privacy","Private · Password" if flow.private_tournament else "Public · Listed in the arena",Rect2(x,y,w,48),"privacy"); y += 56
	if flow.private_tournament:
		_field("password","Password (1–64 characters)",flow.password,Rect2(x,y,w,48),true); y += 56
	_label("Fills early? The tournament starts in 10 seconds. Fewer than 3 players at start time cancels it.",Rect2(x,y,w,76),18); y += 84
	_button("create_tournament","Create Tournament",Rect2(x,y,w,52),"create","",true); controls.create_tournament.disabled = flow.busy; y += 64
	_button("account","Your Screen Name & Hero",Rect2(x,y,w,48),"account"); y += 60
	var left_height = y
	if wide: x = w+32; y = 0
	else: y += 12
	_label("JOIN A TOURNAMENT",Rect2(x,y,w,34),24,P.GOLD,true); y += 42
	var field = _field("room_code","Tournament code · T + 5 letters",flow.join_code,Rect2(x,y,w,48)); field.max_length = 6; y += 56
	_field("join_password","Password (private tournaments)",flow.join_password,Rect2(x,y,w,48),true)
	y += 56
	_button("join_tournament","Join by Code",Rect2(x,y,w,48),"join"); controls.join_tournament.disabled = flow.busy; y += 64
	_label("PUBLIC TOURNAMENTS",Rect2(x,y,w-112,32),18,P.GOLD)
	_button("refresh","Refresh",Rect2(x+w-108,y-6,108,44),"refresh"); y += 46
	if flow.listing.is_empty():
		_label("No public tournaments yet.\nCreate one and invite your rivals.",Rect2(x,y,w,70),19); y += 78
	for entry in flow.listing:
		var label = "%s · %d / %d · %s" % [str(entry.get("host","Player")),int(entry.get("joined",0)),int(entry.get("size",8)),str(entry.get("code",""))]
		_button("join_"+str(entry.get("code","")),label,Rect2(x,y,w,68),"join",str(entry.get("code","")))
		y += 76
	var scroll = ScrollContainer.new(); scroll.position = Vector2(16,108); scroll.size = Vector2(size.x-32,size.y-196)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED; add_child(scroll)
	_body = Control.new(); _body.custom_minimum_size = Vector2(size.x-48,maxf(y,left_height)+16); scroll.add_child(_body)
	for child in get_children():
		if child not in before and child != scroll: child.reparent(_body,false)
	_status(Rect2(24,size.y-82,size.x-48,74)); set_status(flow.status)
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
		# Rebuild for lobby entries/state, preserving drafts in the flow.
		flow.main._rebuild(); return
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
