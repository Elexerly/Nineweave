extends Control
## Online-only chrome. Existing title, board and cinematic drawing stay untouched.
const P = preload("res://ui/paint.gd")
const ButtonArt = preload("res://ui/ornate_button.gd")
const Roster = preload("res://characters/roster.gd")
const HeroRig = preload("res://characters/art.gd")
const ChatPanel = preload("res://ui/chat_panel.gd")
const TERMS_URL = "https://nineweave.grok.me/terms"
const PRIVACY_URL = "https://nineweave.grok.me/privacy"
const AGREEMENT = "By creating a screen name, you agree to our Terms of Service and Privacy Policy and confirm you are 13 or older or have a parent or guardian's permission."
signal action(kind: String, value: String)
signal draft_changed(kind: String, value: String)
var screen: String = "lobby"
var screen_name: String = ""
var room_code: String = ""
var password: String = ""
var status: String = ""
var rooms: Array = []
var players: Array = []
var me: Dictionary = {}
var private_room: bool = false
var local_demo: bool = false
var busy: bool = false
var controls: Dictionary = {}
var list: VBoxContainer
var agreement: RichTextLabel
var link_opener: Callable
var status_label: Label
var _name_rect: Rect2
var _panel: Rect2
## Round 5a waiting room.
var hero_id: String = "vesper_vale"
var opponent_name: String = ""
var opponent_hero: String = ""
var joined: bool = false
var chat_button: bool = false
var chat_unread: int = 0
var reduced_motion: bool = false
var _you_rect: Rect2
var _opp_rect: Rect2
class PublicRoomButton extends "res://ui/ornate_button.gd":
	var host_name: String
	var hero_name: String
	var room: String
	func _draw():
		super._draw()
		P.text(self,host_name,Rect2(12,5,size.x-110,30),20,P.PALE,P.SANS,HORIZONTAL_ALIGNMENT_LEFT)
		P.text(self,room,Rect2(size.x-92,5,80,30),20,P.BLUE)
		P.text(self,hero_name,Rect2(12,35,size.x-24,24),17,P.WHITE,P.SANS,HORIZONTAL_ALIGNMENT_LEFT)
func _ready():
	mouse_filter = Control.MOUSE_FILTER_STOP if screen == "onboarding" else Control.MOUSE_FILTER_IGNORE
	match screen:
		"onboarding": _onboarding()
		"account_welcome": _account_welcome()
		"leaderboard": _leaderboard()
		"waiting": _waiting()
		"private": _private_form()
		_: _lobby()
func _button(id: String, caption: String, rect: Rect2, kind: String, value: String = "", accent: bool = false):
	var button = ButtonArt.new(); button.name = id; button.caption = caption; button.font_size = 20
	button.position = rect.position; button.size = rect.size; button.accent = accent
	button.pressed.connect(func(): action.emit(kind,value)); add_child(button); controls[id] = button
	return button
func _label(value: String, rect: Rect2, font_size: int = 18, color: Color = P.WHITE, serif: bool = false) -> Label:
	var label = Label.new(); label.text = value; label.position = rect.position; label.size = rect.size
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_override("font",P.SERIF if serif else P.SANS); label.add_theme_font_size_override("font_size",font_size)
	label.add_theme_color_override("font_color",color); label.mouse_filter = Control.MOUSE_FILTER_IGNORE; add_child(label)
	return label
func _field(id: String, placeholder: String, value: String, rect: Rect2, secret: bool = false) -> LineEdit:
	var field = LineEdit.new(); field.name = id; field.text = value; field.placeholder_text = placeholder
	field.secret = secret; field.max_length = 64 if secret else (24 if id == "screen_name" else 5)
	field.position = rect.position; field.size = rect.size
	field.add_theme_font_override("font",P.SANS); field.add_theme_font_size_override("font_size",20)
	field.add_theme_color_override("font_color",P.PALE); field.add_theme_color_override("font_placeholder_color",P.WHITE)
	field.add_theme_color_override("caret_color",P.BLUE)
	var style = StyleBoxFlat.new(); style.bg_color = P.NAVY; style.border_color = P.GOLD; style.set_border_width_all(1)
	style.content_margin_left = 12; field.add_theme_stylebox_override("normal",style); field.add_theme_stylebox_override("focus",style)
	field.text_changed.connect(func(text): draft_changed.emit(id,text))
	add_child(field); controls[id] = field; return field
func _header(title: String, back_kind: String = "home"):
	_button("back","Menu" if back_kind == "home" else "Back",Rect2(16,12,100,44),back_kind)
	_label(title,Rect2(22,62,size.x-44,34),25,P.PALE,true)
func _status(rect: Rect2):
	status_label = _label(status,rect,18,P.PALE)
func set_status(value: String):
	status = value
	if is_instance_valid(status_label): status_label.text = value
func _account_welcome():
	var w = minf(440,size.x-48); var x = (size.x-w)*.5; var y = maxf(24,(size.y-300)*.5)
	_panel = Rect2(x-12,y-20,w+24,300)
	_label("ENTER LEXERLY",Rect2(x,y,w,50),25,P.PALE,true)
	_label("New challenger or returning player?",Rect2(x,y+54,w,48),18)
	_button("begin_create","Create Account",Rect2(x,y+118,w,52),"begin_create","",true)
	_button("sign_in","Sign In",Rect2(x,y+184,w,52),"sign_in")

func _onboarding():
	# Use the same scrollable, standard input pattern as the working sign-in form.
	# No auto-focus, invisible input overlay or custom-painted field.
	var width = minf(620,size.x-24)
	_panel = Rect2((size.x-width)*.5,12,width,size.y-24)
	var scroll = ScrollContainer.new(); scroll.position = _panel.position+Vector2(18,18)
	scroll.size = _panel.size-Vector2(36,36); scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED; add_child(scroll)
	var box = VBoxContainer.new(); box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation",14); scroll.add_child(box)
	_form_label(box,"CREATE ACCOUNT",28)
	_form_label(box,"Choose the screen name your rivals will remember.",18)
	_form_label(box,"SCREEN NAME",16)
	var field = LineEdit.new(); field.name = "screen_name"; field.text = screen_name
	field.placeholder_text = "Your screen name"; field.max_length = 24; field.custom_minimum_size.y = 52; field.editable = not busy
	var style = StyleBoxFlat.new(); style.bg_color = Color(1,1,1,.98); style.border_color = Color("8796ad")
	style.set_border_width_all(1); style.set_corner_radius_all(5); style.content_margin_left = 12; style.content_margin_right = 12
	for state in ["normal","focus","read_only"]: field.add_theme_stylebox_override(state,style)
	field.add_theme_color_override("font_color",Color("17243b")); field.add_theme_color_override("font_placeholder_color",Color("53627a"))
	field.add_theme_color_override("caret_color",Color("17243b")); field.add_theme_font_size_override("font_size",18)
	field.text_changed.connect(func(value): draft_changed.emit("screen_name",value))
	field.text_submitted.connect(func(value): if not busy: action.emit("register",value))
	box.add_child(field); controls.screen_name = field
	agreement = RichTextLabel.new(); agreement.name = "Agreement"; agreement.bbcode_enabled = true
	agreement.fit_content = true; agreement.scroll_active = false; agreement.custom_minimum_size.y = 120
	agreement.add_theme_font_override("normal_font",P.SANS); agreement.add_theme_font_size_override("normal_font_size",18)
	agreement.add_theme_color_override("default_color",Color("17243b"))
	agreement.text = "By creating a screen name, you agree to our [url=%s]Terms of Service[/url] and [url=%s]Privacy Policy[/url] and confirm you are 13 or older or have a parent or guardian's permission." % [TERMS_URL,PRIVACY_URL]
	agreement.meta_clicked.connect(open_legal); box.add_child(agreement)
	_form_button(box,"create_name","Create Account","register",true).disabled = busy
	status_label = _form_label(box,status,18)
	_form_button(box,"account_back","Back","account_back").disabled = busy
	_form_button(box,"sign_in","Already a player? Sign In","sign_in").disabled = busy

func _form_label(box: VBoxContainer, value: String, font_size: int) -> Label:
	var label = Label.new(); label.text = value; label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_override("font",P.SANS); label.add_theme_font_size_override("font_size",font_size)
	label.add_theme_color_override("font_color",Color("17243b")); box.add_child(label); return label
func _form_button(box: VBoxContainer, id: String, caption: String, kind: String, accent: bool = false):
	var button = ButtonArt.new(); button.name = id; button.caption = caption; button.font_size = 18
	button.custom_minimum_size.y = 56; button.accent = accent
	button.pressed.connect(func(): action.emit(kind,"")); box.add_child(button); controls[id] = button; return button
func _lobby():
	_header("THE CELESTIAL ARENA")
	_button("leaderboard","Leaderboard",Rect2(size.x-164,12,148,44),"leaderboard")
	var wide = size.x > size.y
	var width = minf(380,size.x*.46) if wide else minf(460,size.x-40)
	var x = size.x-width-20 if wide else (size.x-width)/2
	var y = 104.0
	_button("create","Create Public Game",Rect2(x,y,width,44),"create_public","",true)
	_button("private","Private Rooms",Rect2(x,y+50,width,44),"private")
	var field = _field("room_code","Room code",room_code,Rect2(x,y+100,width*.59,44))
	field.text_submitted.connect(func(value): action.emit("join",value))
	_button("join","Join",Rect2(x+width*.62,y+100,width*.38,44),"join")
	_button("demo","Try Local Online Demo",Rect2(x,y+150,width,44),"demo")
	var left = 20.0 if wide else x
	var list_y = 104.0 if wide else y+204
	var list_width = size.x-width-56 if wide else width
	_label("PUBLIC GAMES · TAP TO JOIN",Rect2(left,list_y,list_width,28),16,P.GOLD)
	var h = size.y-list_y-112
	_make_list(Rect2(left,list_y+32,list_width,maxf(48,h)))
	set_rooms(rooms)
	_status(Rect2(left,size.y-70,list_width if wide else size.x-40,62))
func _make_list(rect: Rect2):
	var scroll = ScrollContainer.new(); scroll.position = rect.position; scroll.size = rect.size
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED; add_child(scroll)
	list = VBoxContainer.new(); list.size_flags_horizontal = Control.SIZE_EXPAND_FILL; list.add_theme_constant_override("separation",6)
	scroll.add_child(list)
func _clear_list():
	for child in list.get_children(): list.remove_child(child); child.queue_free()
func set_rooms(value: Array):
	rooms = value
	if not is_instance_valid(list): return
	_clear_list()
	if rooms.is_empty():
		var empty = Label.new(); empty.text = "No public games yet.\nCreate one and invite a rival."; empty.add_theme_font_override("font",P.SANS)
		empty.add_theme_font_size_override("font_size",18); empty.add_theme_color_override("font_color",P.WHITE); list.add_child(empty)
	for room in rooms:
		var button = PublicRoomButton.new(); button.custom_minimum_size = Vector2(0,66)
		button.host_name = str(room.get("host_name","Player")); button.hero_name = Roster.get_hero(str(room.get("host_hero",""))).name
		button.room = str(room.get("code","")); button.tooltip_text = button.host_name+" · "+button.hero_name+" · "+button.room
		button.pressed.connect(func(): action.emit("join",str(room.get("code","")))); list.add_child(button)
func _private_form():
	_header("PRIVATE ROOMS","lobby")
	var w = minf(440,size.x-40); var x = (size.x-w)/2
	_label("Share your code and password with a friend.",Rect2(x,104,w,40),18)
	_field("password","Password (1–64 characters)",password,Rect2(x,152,w,48),true)
	_button("create_private","Create Private Game",Rect2(x,210,w,48),"create_private","",true)
	_field("room_code","Five-character room code",room_code,Rect2(x,270,w,48))
	_button("join_private","Join Private Room",Rect2(x,328,w,48),"join_private")
	_status(Rect2(x,390,w,80))
	if size.y < 490:
		# Two columns keep all private-room actions accessible in short landscape.
		var half = (size.x-56)*.5
		controls.password.position = Vector2(20,108); controls.password.size = Vector2(half,44)
		controls.create_private.position = Vector2(20,162); controls.create_private.size = Vector2(half,44)
		controls.room_code.position = Vector2(36+half,108); controls.room_code.size = Vector2(half,44)
		controls.join_private.position = Vector2(36+half,162); controls.join_private.size = Vector2(half,44)
		# The explanatory line is replaced by the field placeholders in this layout.
		for child in get_children():
			if child is Label and child != status_label and child.position.y == 104: child.visible = false
		status_label.position = Vector2(20,220); status_label.size = Vector2(size.x-40,80)
func _waiting():
	# Round 5a: code, both seats with hero + screen name, Leave (no penalty) and chat.
	var wide = size.x > size.y and size.y < 600
	var title = (opponent_name+" joined") if joined else ("LOCAL ONLINE DEMO" if local_demo else "Waiting for other player…")
	var privacy = "LOCAL DEMO" if local_demo else ("PRIVATE GAME · share code + password" if private_room else "PUBLIC GAME · listed in the lobby")
	if joined: privacy = "Get ready — the match is starting"
	var col_w = (size.x-56)*.5 if wide else minf(460,size.x-40)
	var x = 20.0 if wide else (size.x-col_w)/2
	var y = 12.0 if wide else maxf(20,size.y*.03)
	var top = y
	var title_label = _label(title,Rect2(x,y,col_w,40),P.fit_size(title,col_w-(60 if wide and chat_button else 12),22 if wide else 25,P.SERIF),P.PALE,true); title_label.name = "WaitingTitle"
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; title_label.autowrap_mode = TextServer.AUTOWRAP_OFF; title_label.clip_text = true
	y += 44 if wide else 52
	if not wide: _label("ROOM CODE",Rect2(x,y,col_w,20),14,P.GOLD).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; y += 20
	var code_label = _label(room_code,Rect2(x,y,col_w,54 if wide else 60),40 if wide else 48,P.PALE,true); code_label.name = "RoomCode"
	code_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	y += 54 if wide else 62
	var line = _label(privacy,Rect2(x,y,col_w,26),16 if wide else 17,P.BLUE); line.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	y += 32
	var row_w = col_w
	_button("copy","Copy code",Rect2(x,y,row_w*.48,44),"copy")
	_button("cancel","Leave",Rect2(x+row_w*.52,y,row_w*.48,44),"lobby")
	_panel = Rect2(x-10,top-8,col_w+20,y+44+12-top)
	y += 52
	if local_demo: _button("demo_join","Invite demo rival",Rect2(x,y,col_w,44),"invite","",true); y += 52
	if chat_button:
		var chat = ChatPanel.ChatButton.new(); chat.name = "chat"; chat.unread = chat_unread
		chat.tooltip_text = "Chat"; chat.pressed.connect(func(): action.emit("chat",""))
		add_child(chat); controls["chat"] = chat
	# Seats: you (left) and the rival slot (right).
	var seats: Rect2
	if wide: seats = Rect2(36+col_w,12,size.x-56-col_w,size.y-24)
	else:
		var bottom = size.y-150
		seats = Rect2(x,y+6,col_w,maxf(150,bottom-y-6))
	var gap = 16.0
	var sw = (seats.size.x-gap)*.5
	var portrait = minf(sw,seats.size.y-62)
	# Centre the two seats in the space left between the code block and Leave.
	seats.position.y += maxf(0,(seats.size.y-portrait-58)*.5)
	_you_rect = Rect2(seats.position.x,seats.position.y,sw,portrait+58)
	_opp_rect = Rect2(seats.position.x+sw+gap,seats.position.y,sw,portrait+58)
	_seat(_you_rect,hero_id,screen_name if not screen_name.is_empty() else "You",1)
	if joined or not opponent_hero.is_empty():
		_seat(_opp_rect,opponent_hero if Roster.valid(opponent_hero) else "auric_rex",opponent_name if not opponent_name.is_empty() else "Rival",-1)
	else:
		var waiting = _label("Waiting…",Rect2(_opp_rect.position.x,_opp_rect.end.y-54,_opp_rect.size.x,26),18,P.MUTED); waiting.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if wide:
		_status(Rect2(x,y,col_w,maxf(40,size.y-y-8)))
		if chat_button:
			controls.chat.position = Vector2(x+col_w-52,12); controls.chat.size = Vector2(52,48)
			title_label.size.x = col_w-60; title_label.position.x = x
	else:
		var by = size.y-140
		if chat_button:
			controls.chat.position = Vector2(x+col_w-56,by); controls.chat.size = Vector2(56,52)
		_status(Rect2(x,by+60,col_w,maxf(40,size.y-by-66)))
		# Leave is the prominent bottom action on phones; Copy stays beside the code.
		controls.cancel.position = Vector2(x,by); controls.cancel.size = Vector2(col_w-(64 if chat_button else 0),52)
		controls.copy.position = Vector2(x+(col_w-col_w*.6)*.5,controls.copy.position.y); controls.copy.size.x = col_w*.6
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
func _process(_delta):
	if screen == "waiting" and not joined and not reduced_motion: queue_redraw()
func _seat(rect: Rect2, id: String, name_value: String, facing: int):
	var size_px = minf(rect.size.x,rect.size.y-58)
	var rig = HeroRig.new(); rig.hero_id = Roster.canonical_id(id) if Roster.valid(id) else "vesper_vale"
	rig.side = 1 if facing > 0 else 2; rig.facing = facing; rig.bust = true; rig.reduced_motion = reduced_motion
	rig.position = Vector2(rect.get_center().x-size_px*.5,rect.position.y+4); rig.size = Vector2(size_px,size_px-6)
	rig.mouse_filter = Control.MOUSE_FILTER_IGNORE; add_child(rig)
	var label = _label(name_value,Rect2(rect.position.x,rect.end.y-54,rect.size.x,26),20,P.WHITE)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; label.autowrap_mode = TextServer.AUTOWRAP_OFF; label.clip_text = true
	label.name = "SeatName" if facing > 0 else "OpponentName"
	var hero = _label(Roster.get_hero(rig.hero_id).name,Rect2(rect.position.x,rect.end.y-28,rect.size.x,22),15,P.GOLD)
	hero.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; hero.autowrap_mode = TextServer.AUTOWRAP_OFF; hero.clip_text = true
func _leaderboard():
	_header("HALL OF VICTORS","lobby")
	var w = minf(640,size.x-40); var x = (size.x-w)/2
	_label("RANK     SCREEN NAME                         MATCHES WON",Rect2(x,104,w,32),16,P.GOLD)
	_make_list(Rect2(x,142,w,maxf(44,size.y-340)))
	for row in players:
		var entry = HBoxContainer.new(); entry.custom_minimum_size.y = 44; entry.add_theme_constant_override("separation",10); list.add_child(entry)
		for key in ["rank","screen_name","matches_won"]:
			var value = row.get(key)
			var label = Label.new(); label.text = "—" if value == null else (str(value) if key == "screen_name" else str(int(value)))
			label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			if key == "screen_name": label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			else: label.custom_minimum_size.x = 40 if key == "rank" else 68
			if key == "matches_won": label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			label.add_theme_font_override("font",P.SANS); label.add_theme_font_size_override("font_size",20); label.add_theme_color_override("font_color",P.WHITE); entry.add_child(label)
	if players.is_empty():
		var empty = Label.new(); empty.text = "The hall awaits its first victors."; empty.add_theme_font_override("font",P.SANS)
		empty.add_theme_font_size_override("font_size",18); list.add_child(empty)
	var own = "Create a screen name to track your online wins."
	if not me.is_empty():
		own = "%s · %d matches won\n%s" % [str(me.get("screen_name",screen_name)),int(me.get("matches_won",0)),("Rank #%d" % int(me.rank)) if int(me.get("matches_played",0)) > 0 and me.get("rank") != null else "Unranked · play a match to appear"]
	_label("YOUR RECORD",Rect2(x,size.y-186,w,26),16,P.GOLD)
	_label(own,Rect2(x,size.y-156,w,72),20,P.PALE)
	_status(Rect2(x,size.y-76,w,66))
	if size.x > size.y and size.y < 500:
		var half = (size.x-60)*.5
		var scroll = list.get_parent(); scroll.position = Vector2(20,142); scroll.size = Vector2(half,size.y-160)
		for child in get_children():
			if child is Label and child != status_label and child.position.y >= size.y-186 and child.text in ["YOUR RECORD",own]:
				child.position = Vector2(40+half,110 if child.text == "YOUR RECORD" else 142); child.size.x = half
		status_label.position = Vector2(40+half,222); status_label.size = Vector2(half,size.y-234)
func open_legal(link):
	if str(link) not in [TERMS_URL,PRIVACY_URL]: return
	if link_opener.is_valid(): link_opener.call(str(link))
	else: OS.shell_open(str(link))
func _draw():
	if screen != "onboarding":
		preload("res://ui/readability.gd").draw_panel(self,readability_rect())
	if screen == "onboarding":
		for i in range(48):
			var t = float(i)/48; var color = Color("ffffff").lerp(Color("dbe5f3"),t); color.a = .97
			draw_rect(Rect2(_panel.position+Vector2(0,_panel.size.y*t),Vector2(_panel.size.x,_panel.size.y/48+1)),color)
	elif _panel.has_area(): P.panel(self,_panel,false,1,true)
	if screen == "waiting" and _you_rect.has_area():
		for r in [_you_rect,_opp_rect]: P.panel(self,r,r == _opp_rect and joined,1,r.size.y >= 120)
		if not joined and opponent_hero.is_empty():
			var c = Vector2(_opp_rect.get_center().x,_opp_rect.position.y+(_opp_rect.size.y-58)*.5)
			var radius = minf(_opp_rect.size.x,_opp_rect.size.y-58)*.3
			var spin = 0.0 if reduced_motion else P.clock*1.4
			for i in range(12):
				var a = spin+i*TAU/12
				draw_arc(c,radius,a,a+TAU/24,6,Color(P.GOLD,.75),2,true)
			P.text(self,"?",Rect2(c-Vector2(radius,radius),Vector2(radius*2,radius*2)),int(radius*1.1),P.PALE,P.SERIF)
	if not _name_rect.has_area(): return
	var r = _name_rect; var field = controls.get("screen_name")
	var edge = P.BLUE if is_instance_valid(field) and field.has_focus() else P.GOLD
	var points = PackedVector2Array([r.position+Vector2(10,0),Vector2(r.end.x,r.position.y),r.end-Vector2(10,0),Vector2(r.position.x,r.end.y)])
	draw_colored_polygon(points,P.NAVY); draw_polyline(points+PackedVector2Array([points[0]]),P.GOLD_DARK,5,true)
	draw_polyline(points+PackedVector2Array([points[0]]),edge,1.5,true)
	draw_line(points[0]+Vector2(3,2),points[3]+Vector2(3,-2),edge,3,true)
	P.diamond(self,Vector2(r.end.x-12,r.position.y+10),3,edge)
	P.text(self,"SCREEN NAME",Rect2(r.position+Vector2(16,1),Vector2(r.size.x-32,16)),12,P.GOLD,P.SANS,HORIZONTAL_ALIGNMENT_LEFT)

func readability_rect() -> Rect2:
	var wide = size.x > size.y
	var w = size.x-minf(380,size.x*.46)-30 if wide and screen == "lobby" else size.x
	return Rect2(0,58,w,maxf(0,size.y-58))
