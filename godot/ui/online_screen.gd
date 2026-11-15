extends Control
## Online-only chrome. Existing title, board and cinematic drawing stay untouched.
const P = preload("res://ui/paint.gd")
const ButtonArt = preload("res://ui/ornate_button.gd")
const Roster = preload("res://characters/roster.gd")
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
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	match screen:
		"onboarding": _onboarding()
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
func _onboarding():
	# Scroll only on short landscape. Phone body stays 18px and never shrinks to fit.
	var width = minf(460,size.x-40); var x = (size.x-width)/2
	var top = maxf(20,(size.y-566)/2)
	if size.y < 600:
		var scroll = ScrollContainer.new(); scroll.position = Vector2(x,12); scroll.size = Vector2(width,size.y-24)
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED; add_child(scroll)
		var content = get_script().new(); content.screen = "onboarding"; content.screen_name = screen_name; content.status = status
		content.busy = busy; content.size = Vector2(width-14,600); content.custom_minimum_size = Vector2(width-14,600)
		content.action.connect(func(kind,value): action.emit(kind,value)); content.draft_changed.connect(func(kind,value): draft_changed.emit(kind,value))
		scroll.add_child(content); controls = content.controls; agreement = content.agreement; status_label = content.status_label; return
	_panel = Rect2(x-10,top,width+20,550)
	_label("ENTER THE NINEWEAVE",Rect2(x+8,top+14,width-16,38),24,P.PALE,true)
	_label("Choose the name your rivals will remember.",Rect2(x+8,top+58,width-16,48),18)
	_name_rect = Rect2(x+8,top+118,width-16,64)
	var field = _field("screen_name","Your screen name",screen_name,_name_rect)
	var empty = StyleBoxEmpty.new(); empty.content_margin_left = 16; empty.content_margin_right = 16; empty.content_margin_top = 14
	for state in ["normal","focus","read_only"]: field.add_theme_stylebox_override(state,empty)
	field.focus_entered.connect(queue_redraw); field.focus_exited.connect(queue_redraw)
	field.text_submitted.connect(func(value): action.emit("register",value))
	agreement = RichTextLabel.new(); agreement.name = "Agreement"; agreement.bbcode_enabled = true
	agreement.position = Vector2(x+8,top+196); agreement.size = Vector2(width-16,128)
	agreement.scroll_active = false; agreement.add_theme_font_override("normal_font",P.SANS)
	agreement.add_theme_font_size_override("normal_font_size",18); agreement.add_theme_color_override("default_color",P.PALE)
	agreement.text = "By creating a screen name, you agree to our [url=%s][color=#9deaff]Terms of Service[/color][/url] and [url=%s][color=#9deaff]Privacy Policy[/color][/url] and confirm you are 13 or older or have a parent or guardian's permission." % [TERMS_URL,PRIVACY_URL]
	agreement.meta_clicked.connect(open_legal)
	add_child(agreement)
	var create = _button("create_name","Create Screen Name",Rect2(x+8,top+330,width-16,52),"register","",true)
	create.disabled = busy
	_button("offline","Play Offline / Main Menu",Rect2(x+8,top+394,width-16,46),"home")
	_status(Rect2(x+8,top+450,width-16,88))
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
	_header("LOCAL ONLINE DEMO" if local_demo else "WAITING FOR A RIVAL")
	var w = minf(440,size.x-40); var x = (size.x-w)/2; var y = maxf(110,size.y*.24)
	if size.y < 450: y = 100
	_label(room_code,Rect2(x,y,w,58),42,P.PALE,true)
	_label("LOCAL DEMO" if local_demo else ("PRIVATE GAME · share code + password" if private_room else "PUBLIC GAME · listed in the lobby"),Rect2(x,y+60,w,32),18,P.BLUE)
	_button("copy","Copy code",Rect2(x,y+104,w*.48,44),"copy")
	_button("cancel","Cancel / Leave",Rect2(x+w*.52,y+104,w*.48,44),"lobby")
	if local_demo: _button("demo_join","Invite demo rival",Rect2(x,y+158,w,44),"invite","",true)
	_status(Rect2(x,y+212 if size.y >= 450 else y+152,w,72 if size.y >= 450 else 54))
	if size.y < 450:
		var half = (size.x-56)*.5
		controls.copy.position = Vector2(36+half,106); controls.copy.size = Vector2(half,44)
		controls.cancel.position = Vector2(36+half,160); controls.cancel.size = Vector2(half,44)
		if local_demo: controls.demo_join.position = Vector2(36+half,214); controls.demo_join.size = Vector2(half,44)
		for child in get_children():
			if child is Label and child != status_label and child.position.y in [y,y+60]: child.size.x = half
		status_label.position = Vector2(20,202); status_label.size = Vector2(half,94)
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
	if _panel.has_area(): P.panel(self,_panel,false,1,true)
	if not _name_rect.has_area(): return
	var r = _name_rect; var field = controls.get("screen_name")
	var edge = P.BLUE if is_instance_valid(field) and field.has_focus() else P.GOLD
	var points = PackedVector2Array([r.position+Vector2(10,0),Vector2(r.end.x,r.position.y),r.end-Vector2(10,0),Vector2(r.position.x,r.end.y)])
	draw_colored_polygon(points,P.NAVY); draw_polyline(points+PackedVector2Array([points[0]]),P.GOLD_DARK,5,true)
	draw_polyline(points+PackedVector2Array([points[0]]),edge,1.5,true)
	draw_line(points[0]+Vector2(3,2),points[3]+Vector2(3,-2),edge,3,true)
	P.diamond(self,Vector2(r.end.x-12,r.position.y+10),3,edge)
	P.text(self,"SCREEN NAME",Rect2(r.position+Vector2(16,1),Vector2(r.size.x-32,16)),12,P.GOLD,P.SANS,HORIZONTAL_ALIGNMENT_LEFT)
