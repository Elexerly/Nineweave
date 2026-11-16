extends Control
## Round 5a in-match chat: message list, quick-chat chips, 120-character input and the
## opponent moderation menu (Mute, Block, Report). Owns no network; the controller sends.
const P = preload("res://ui/paint.gd")
const ButtonArt = preload("res://ui/ornate_button.gd")
const Clock = preload("res://net/turn_clock.gd")
signal send_text(text: String)
signal send_preset(key: String)
signal closed
signal draft_changed(text: String)
## kind: mute, unmute, block, report (reason + note).
signal moderation(kind: String, reason: String, note: String)
var messages: Array = []
var presets: Dictionary = Clock.DEFAULT_PRESETS.duplicate()
var opponent_name: String = ""
var muted: bool = false
var blocked: bool = false
## Off: the notice explains why (no rival yet, no screen name, room closed).
var can_send: bool = true
var can_moderate: bool = true
var notice: String = ""
var status: String = ""
var draft: String = ""
var view: String = "chat"
var report_reason: String = ""
var report_note: String = ""
var controls: Dictionary = {}
var list: VBoxContainer
var scroll: ScrollContainer
var status_label: Label
var counter: Label

## Speech-bubble button with an unread badge.
class ChatButton extends "res://ui/ornate_button.gd":
	var unread: int = 0
	func _draw():
		super._draw()
		var c = size*.5; var s = minf(size.x,size.y)*.2
		var color = P.PALE if not disabled else P.MUTED
		var body = Rect2(c+Vector2(-s*1.15,-s*.9),Vector2(s*2.3,s*1.55))
		var pts = PackedVector2Array([body.position,Vector2(body.end.x,body.position.y),body.end,Vector2(body.position.x+s*.95,body.end.y),Vector2(body.position.x+s*.35,body.end.y+s*.62),Vector2(body.position.x+s*.45,body.end.y),Vector2(body.position.x,body.end.y),body.position])
		draw_polyline(pts,color,maxf(1.6,s*.17),true)
		for i in range(3): draw_circle(body.get_center()+Vector2((i-1)*s*.55,0),s*.13,P.GOLD)
		if unread > 0:
			var bc = Vector2(size.x-11,11)
			draw_circle(bc,9,Color("ff5a4f")); draw_arc(bc,9,0,TAU,24,Color(1,1,1,.85),1.2,true)
			P.text(self,"9+" if unread > 9 else str(unread),Rect2(bc-Vector2(9,9),Vector2(18,18)),12,Color.WHITE,P.SANS)

## Where the panel goes: below the board on phone portrait, in the side column on wide
## layouts, never over the board's cells when there is room for it.
static func panel_rect(layout: Dictionary) -> Rect2:
	var s: Vector2 = layout.size
	var board: Rect2 = layout.get("board",Rect2())
	if layout.get("mode","") == "phone_portrait":
		var top = board.end.y+4
		if s.y-top-6 >= 230: return Rect2(6,top,s.x-12,s.y-top-6)
		return Rect2(6,s.y-236,s.x-12,230)
	var info: Rect2 = layout.get("info",Rect2())
	if info.size.x >= 240 and info.size.y >= 240: return info
	# Beside the board when a side has room, else a bottom-right sheet.
	var right = s.x-board.end.x-16
	var w = minf(360,s.x-16); var h = minf(320,s.y-16)
	if right >= 260: w = minf(w,right); return Rect2(s.x-w-8,s.y-h-8,w,h)
	if board.position.x-16 >= 260: w = minf(w,board.position.x-16); return Rect2(8,s.y-h-8,w,h)
	return Rect2(s.x-w-8,s.y-h-8,w,h)

func _ready():
	mouse_filter = Control.MOUSE_FILTER_STOP
	var w = size.x; var h = size.y
	var title = "Chat"
	if not opponent_name.is_empty() and can_moderate:
		var who = _button("opponent_menu",opponent_name+"  ▾",Rect2(8,6,w-66,44),func(): show_view("chat" if view == "menu" else "menu"))
		who.font_size = 18
	else:
		_label(title if opponent_name.is_empty() else "Chat · "+opponent_name,Rect2(16,6,w-80,44),18,P.PALE)
	_button("chat_close","×",Rect2(w-54,6,46,44),func(): closed.emit()).font_size = 28
	match view:
		"menu": _menu(w)
		"block": _block_confirm(w)
		"report": _report(w,h)
		_: _chat(w,h)
func _chat(w: float, h: float):
	var input_y = h-52; var chips_y = input_y-46; var status_y = chips_y-22
	scroll = ScrollContainer.new(); scroll.name = "ChatScroll"; scroll.position = Vector2(10,54); scroll.size = Vector2(w-20,maxf(30,status_y-56))
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED; add_child(scroll)
	list = VBoxContainer.new(); list.size_flags_horizontal = Control.SIZE_EXPAND_FILL; list.add_theme_constant_override("separation",4); scroll.add_child(list)
	set_messages(messages)
	status_label = _label(status if not status.is_empty() else notice,Rect2(12,status_y,w-24,20),14,P.GOLD)
	status_label.name = "ChatStatus"; status_label.autowrap_mode = TextServer.AUTOWRAP_OFF; status_label.clip_text = true
	var chips = ScrollContainer.new(); chips.name = "Presets"; chips.position = Vector2(8,chips_y); chips.size = Vector2(w-16,44)
	chips.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED; add_child(chips)
	var row = HBoxContainer.new(); row.add_theme_constant_override("separation",6); chips.add_child(row)
	for key in presets:
		var chip = ButtonArt.new(); chip.name = "preset_"+key; chip.caption = presets[key]; chip.font_size = 16
		chip.custom_minimum_size = Vector2(P.text_width(presets[key],16)+30,44); chip.disabled = not can_send
		chip.pressed.connect(func(): send_preset.emit(key)); row.add_child(chip); controls[chip.name] = chip
	var field = LineEdit.new(); field.name = "chat_input"; field.max_length = Clock.CHAT_LIMIT; field.text = draft
	field.placeholder_text = "Say something kind…" if can_send else "Chat unavailable"; field.editable = can_send
	field.position = Vector2(8,input_y); field.size = Vector2(w-16-84,44)
	field.add_theme_font_override("font",P.SANS); field.add_theme_font_size_override("font_size",18)
	field.add_theme_color_override("font_color",P.PALE); field.add_theme_color_override("font_placeholder_color",P.MUTED)
	var style = StyleBoxFlat.new(); style.bg_color = Color("041425"); style.border_color = P.GOLD_DARK.lightened(.35)
	style.set_border_width_all(1); style.set_corner_radius_all(6); style.content_margin_left = 10; style.content_margin_right = 52
	field.add_theme_stylebox_override("normal",style); field.add_theme_stylebox_override("focus",style); field.add_theme_stylebox_override("read_only",style)
	field.text_changed.connect(func(value): draft = value; _count(); draft_changed.emit(value))
	field.text_submitted.connect(func(value): _submit(value))
	add_child(field); controls.chat_input = field
	counter = _label("",Rect2(w-16-84-50,input_y,44,44),13,P.MUTED); counter.name = "ChatCounter"
	counter.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT; _count()
	var send = _button("chat_send","Send",Rect2(w-84,input_y,76,44),func(): _submit(controls.chat_input.text),true)
	send.disabled = not can_send
func _count():
	if is_instance_valid(counter): counter.text = "%d/%d" % [draft.length(),Clock.CHAT_LIMIT]
func _submit(value: String):
	if not can_send: return
	var clean = Clock.clean_chat(value)
	if clean.is_empty(): return
	send_text.emit(clean)
## Called by the controller after a successful send.
func clear_draft():
	draft = ""
	if controls.has("chat_input") and is_instance_valid(controls.chat_input): controls.chat_input.text = ""
	_count()
func _menu(w: float):
	var y = 58.0
	_button("mute","Unmute" if muted else "Mute (this match)",Rect2(16,y,w-32,44),func(): moderation.emit("unmute" if muted else "mute","",""))
	var block = _button("block","Blocked" if blocked else "Block",Rect2(16,y+50,w-32,44),func(): show_view("block"))
	block.disabled = blocked
	_button("report","Report",Rect2(16,y+100,w-32,44),func(): report_reason = ""; report_note = ""; show_view("report"))
	_button("menu_back","Back to chat",Rect2(16,y+150,w-32,44),func(): show_view("chat"))
	status_label = _label(status,Rect2(16,y+198,w-32,22),14,P.GOLD)
func _block_confirm(w: float):
	var text = _label("Block %s? You won't see their messages, and you won't be matched in each other's rooms." % opponent_name,Rect2(16,58,w-32,88),17,P.PALE)
	text.name = "BlockCopy"
	_button("block_confirm","Block",Rect2(16,154,(w-40)*.5,44),func(): moderation.emit("block","",""),true)
	_button("block_cancel","Cancel",Rect2(24+(w-40)*.5,154,(w-40)*.5,44),func(): show_view("menu"))
	status_label = _label(status,Rect2(16,204,w-32,22),14,P.GOLD)
func _report(w: float, h: float):
	var cw = (w-32-12)/3.0
	for i in range(Clock.REPORT_REASONS.size()):
		var pair = Clock.REPORT_REASONS[i]
		var chip = _button("reason_"+pair[0],pair[1],Rect2(16+(i%3)*(cw+6),56+int(i/3)*48,cw,44),func(): report_reason = pair[0]; _mark_reason())
		chip.font_size = 15
	_mark_reason()
	var note = LineEdit.new(); note.name = "report_note"; note.max_length = Clock.NOTE_LIMIT; note.text = report_note
	note.placeholder_text = "Optional note (500 characters max)"; note.position = Vector2(16,156); note.size = Vector2(w-32,44)
	note.add_theme_font_override("font",P.SANS); note.add_theme_font_size_override("font_size",16); note.add_theme_color_override("font_color",P.PALE)
	note.add_theme_color_override("font_placeholder_color",P.MUTED)
	var style = StyleBoxFlat.new(); style.bg_color = Color("041425"); style.border_color = P.GOLD_DARK.lightened(.35); style.set_border_width_all(1); style.set_corner_radius_all(6); style.content_margin_left = 10
	note.add_theme_stylebox_override("normal",style); note.add_theme_stylebox_override("focus",style)
	note.text_changed.connect(func(value): report_note = value)
	add_child(note); controls.report_note = note
	var y = minf(206,h-50)
	var submit = _button("report_send","Send report",Rect2(16,y,(w-40)*.58,44),func():
		if report_reason.is_empty(): set_status("Choose a reason first."); return
		moderation.emit("report",report_reason,report_note.strip_edges().left(Clock.NOTE_LIMIT)),true)
	submit.font_size = 17
	_button("report_cancel","Cancel",Rect2(24+(w-40)*.58,y,(w-40)*.42,44),func(): show_view("menu"))
	status_label = _label(status,Rect2(16,y+46,w-32,maxf(0,minf(22,h-y-46))),14,P.GOLD)
func _mark_reason():
	for pair in Clock.REPORT_REASONS:
		var id = "reason_"+pair[0]
		if controls.has(id): controls[id].accent = report_reason == pair[0]
func show_view(value: String):
	view = value; status = ""
	for child in get_children(): remove_child(child); child.queue_free()
	controls.clear(); list = null; scroll = null; status_label = null; counter = null
	_ready(); queue_redraw()
func set_status(value: String):
	status = value
	if is_instance_valid(status_label): status_label.text = value if not value.is_empty() else (notice if view == "chat" else "")
func set_messages(value: Array):
	messages = value
	if not is_instance_valid(list): return
	for child in list.get_children(): list.remove_child(child); child.queue_free()
	if messages.is_empty():
		var empty = Label.new(); empty.text = "No messages yet. Quick chat below." if can_send else notice
		empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; empty.add_theme_font_override("font",P.SANS)
		empty.add_theme_font_size_override("font_size",15); empty.add_theme_color_override("font_color",P.MUTED); list.add_child(empty)
	for m in messages:
		var line = RichTextLabel.new(); line.bbcode_enabled = true; line.fit_content = true; line.scroll_active = false
		line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		line.add_theme_font_override("normal_font",P.SANS); line.add_theme_font_size_override("normal_font_size",16)
		line.add_theme_color_override("default_color",P.WHITE); line.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var who = "You" if m.get("mine",false) else str(m.get("name",""))
		var body = "[color=#%s]%s[/color]  %s" % [("42dcff" if m.get("mine",false) else "d6ad65"),escape(who),escape(str(m.get("text","")))]
		line.text = "[right]"+body+"[/right]" if m.get("mine",false) else body
		line.set_meta("mine",bool(m.get("mine",false))); line.set_meta("id",int(m.get("id",0)))
		list.add_child(line)
	call_deferred("_scroll_end")
func _scroll_end():
	if is_instance_valid(scroll): scroll.scroll_vertical = int(scroll.get_v_scroll_bar().max_value)
static func escape(value: String) -> String:
	return value.replace("[","[lb]")
func _button(id: String, caption: String, rect: Rect2, callback: Callable, accent: bool = false):
	var button = ButtonArt.new(); button.name = id; button.caption = caption; button.font_size = 18
	button.position = rect.position; button.size = rect.size; button.accent = accent
	button.pressed.connect(callback); add_child(button); controls[id] = button
	return button
func _label(value: String, rect: Rect2, font_size: int, color: Color) -> Label:
	var label = Label.new(); label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; label.text = value; label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_override("font",P.SANS); label.add_theme_font_size_override("font_size",font_size)
	label.add_theme_color_override("font_color",color); label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.position = rect.position; label.size = rect.size; add_child(label)
	return label
func _draw():
	var r = Rect2(Vector2.ZERO,size)
	draw_colored_polygon(P.polygon(r.grow(-2)),Color(.008,.03,.07,.97))
	P.panel(self,r,false,1,true)
	draw_line(Vector2(12,52),Vector2(size.x-12,52),Color(P.GOLD,.35),1)
