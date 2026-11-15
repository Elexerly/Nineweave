extends SceneTree
## Round 3e: portrait-phone board size (Safari-short viewports), byte-identical layouts for
## every other mode (snapshot from Round 3c), Undo/Hint only vs the computer, and the
## warm-gold last-move highlight.
const Main = preload("res://main/main.tscn")
const Store = preload("res://settings/store.gd")
const Profile = preload("res://characters/profile.gd")
const Layout = preload("res://ui/layout.gd")
const Board = preload("res://ui/board.gd")
const Cinema = preload("res://characters/cinematic.gd")
const Rules = preload("res://kernel/rules.gd")
const PHONES = [[360,640],[375,667],[390,844],[393,852],[430,932],[360,780],[390,664],[390,620],[375,553],[430,740],[360,600]]
const SNAPSHOT = "res://tests/layout_snapshot_r3c.json"
var checks = 0
var failures = 0
func ok(value: bool, msg: String):
	checks += 1
	if not value: failures += 1; print("FAIL ",msg)
func _initialize(): run.call_deferred()
func frames(count: int = 2):
	for i in range(count): await process_frame

func run():
	phone_portrait()
	snapshot()
	var ui = Main.instantiate(); ui.settings = Store.new("user://r3e-ui.cfg"); ui.profile = Profile.new("user://r3e-profile.cfg")
	ui.settings.values.sound = false; ui.settings.values.reduced_motion = false; ui.profile.data.onboarded = true
	root.add_child(ui); await frames()
	await undo_hint(ui)
	await last_move(ui)
	ui.queue_free(); await frames(3)
	print("NINEWEAVE_ROUND3E ","PASS" if failures == 0 else "FAIL"," checks=",checks," failures=",failures)
	quit(0 if failures == 0 else 1)

# ------------------------------------------------------------ a) phone portrait
func phone_portrait():
	for size in PHONES:
		var s = Vector2(size[0],size[1]); var l = Layout.compute(s); var id = str(s)
		var view = Rect2(Vector2.ZERO,s)
		ok(l.mode == "phone_portrait",id+" phone_portrait")
		var b: Rect2 = l.board
		ok(b.size.x >= .92*s.x,id+" board width %.1f >= 92%%" % b.size.x)
		ok(b.size.x == b.size.y,id+" board square")
		ok(view.encloses(b),id+" board inside view")
		var cr: Rect2 = l.controls
		ok(view.encloses(cr) and cr.end.y <= s.y-8,id+" controls inside with 8 px bottom margin "+str(cr))
		# The X/O tiles overhang the control row (main._draw_game); they keep the margin too.
		var tile = minf(cr.size.y+8,84)
		ok(cr.position.y-4+tile <= s.y-8,id+" X/O tiles keep 8 px bottom margin")
		ok(l.touch >= 44 and cr.size.y >= 44 and l.header.size.y >= 44,id+" 44 px touch targets")
		ok(l.info.size.y == 0,id+" no info panel")
		ok(l.message.size.y > 0 and l.message.size.y <= 16,id+" slim message lane")
		var rects = {"board":b,"players":l.players,"turn":l.turn,"controls":cr,"message":l.message,
			"home":Rect2(l.header.position,Vector2(44,44)),"settings":Rect2(l.header.end.x-44,l.header.position.y,44,44),
			"tiles":Rect2(cr.position.x,cr.position.y-4,cr.size.x,tile),
			"hero_player":l.hero_player,"hero_opponent":l.hero_opponent}
		ok(l.header.encloses(l.turn),id+" turn sits inside the header row")
		var keys = rects.keys()
		for i in range(keys.size()):
			var a: Rect2 = rects[keys[i]]
			if a.size.x <= 0 or a.size.y <= 0: continue
			ok(view.encloses(a),id+" inside "+keys[i])
			for j in range(i+1,keys.size()):
				var z: Rect2 = rects[keys[j]]
				if z.size.x <= 0 or z.size.y <= 0: continue
				if [keys[i],keys[j]] in [["controls","tiles"]]: continue
				ok(not a.intersects(z),id+" no overlap %s %s / %s %s" % [keys[i],a,keys[j],z])
		for key in ["hero_player","hero_opponent"]:
			if l[key].size.y > 0: ok(l[key].size.y >= Layout.PHONE_CORNER_MIN and l[key].position.y > cr.end.y,id+" readable bust under controls "+key)
	var tall = Layout.compute(Vector2(390,844)); var short = Layout.compute(Vector2(390,620))
	ok(tall.hero_player.size.y >= 90 and tall.hero_opponent.size.y >= 90,"390x844 keeps both corner busts")
	ok(short.hero_player.size.y == 0 and short.board.size.x >= 350,"390x620 board >= 350, no busts")
	var safari = Layout.compute(Vector2(390,664))
	var above = safari.board.position.y-safari.players.end.y; var below = safari.controls.position.y-safari.message.end.y
	ok(absf(above-below) <= 8,"390x664 board block centred between chrome and controls (%.0f / %.0f)" % [above,below])

# ------------------------------------------------------------ b) other modes byte-identical
func to_value(v):
	if v is Array and v.size() == 4: return Rect2(v[0],v[1],v[2],v[3])
	if v is Array and v.size() == 2: return Vector2(v[0],v[1])
	return v
func snapshot():
	var text = FileAccess.get_file_as_string(SNAPSHOT)
	var data = JSON.parse_string(text)
	ok(data is Dictionary and data.size() >= 17,"snapshot loads")
	if not data is Dictionary: return
	var hinges = {"867x553+hinge":Rect2(426,0,15,553),"2601x1659+hinge":Rect2(1278,0,45,1659)}
	for key in data:
		var dims = str(key).split("+")[0].split("x")
		var l = Layout.compute(Vector2(float(dims[0]),float(dims[1])),hinges.get(key,Rect2()))
		var want: Dictionary = data[key]
		var got_keys: Array = []; var want_keys: Array = []
		for k in l: got_keys.append(str(k))
		for k in want: want_keys.append(str(k))
		got_keys.sort(); want_keys.sort()
		ok(got_keys == want_keys,"%s same keys %s vs %s" % [key,got_keys,want_keys])
		for k in want:
			var expected = to_value(want[k]); var actual = l.get(k)
			var same = false
			if expected is float and actual is float: same = expected == actual
			elif expected is float: same = float(expected) == float(actual)
			else: same = typeof(expected) == typeof(actual) and expected == actual
			ok(same,"%s %s identical: %s vs snapshot %s" % [key,k,actual,expected])

# ------------------------------------------------------------ c) Undo / Hint only vs computer
func undo_hint(ui):
	var sizes = [Vector2(390,844),Vector2(390,620),Vector2(844,390),Vector2(768,1024),Vector2(669,787),Vector2(867,553),Vector2(1366,1024),Vector2(1920,1080)]
	for s in sizes:
		ui.set_view_size(s); await frames(1)
		ui.start_game("computer",1); ui.thinking = false
		ok(ui.controls.has("undo") and ui.controls.has("hint") and ui.controls.undo.visible and ui.controls.hint.visible,"%s computer shows Undo/Hint" % s)
		ui.start_game("local")
		ok(not ui.controls.has("undo") and not ui.controls.has("hint"),"%s pass-and-play hides Undo/Hint" % s)
		for child in ui.get_children():
			if child is BaseButton: ok(not child.name in ["undo","hint"] and not (child.get("caption") in ["Undo","Hint"]),"%s no stray Undo/Hint button" % s)
	ui.set_view_size(Vector2(390,844))
	ui.start_game("local"); ui._input_beat = 0; ui.play_cell(4,4)
	ok(not ui.undo_move() and ui.game.history.size() == 1,"local undo_move guarded")
	ui.request_hint(); ok(not ui.hint_busy,"local request_hint guarded")
	# Online (demo loopback rival): no buttons, both calls refused.
	ui.create_online(true); ui.invite_demo_rival(); await frames(1)
	ok(ui.mode == "online" and ui.page == "game","online match")
	ok(not ui.controls.has("undo") and not ui.controls.has("hint"),"online hides Undo/Hint")
	ok(not ui.undo_move(),"online undo_move guarded")
	ui.request_hint(); ok(not ui.hint_busy,"online request_hint guarded")
	ui.go_home(); await frames(1)

# ------------------------------------------------------------ d) last move highlight
func last_move(ui):
	var gold: Color = Board.LAST_MOVE_GOLD
	ok(gold.r > .9 and gold.g > .7 and gold.b < .5,"last-move colour is warm gold "+str(gold))
	ok(Board.LAST_MOVE_FILL_ALPHA >= .14 and Board.LAST_MOVE_FILL_ALPHA <= .22,"gold fill stays translucent over the piece")
	ui.set_view_size(Vector2(390,844)); ui.start_game("computer",1); ui.thinking = false
	var board = ui.board
	ui._input_beat = 0; ui.play_cell(4,4); ui.thinking = false
	board.game.play(4,0); ui._refresh_labels()
	ok(board.last_move == Vector2i(4,0) and not board.last_move_whole,"opponent move highlighted")
	var t: Rect2 = board.tile_rect(4).grow(-board.size.x*.018); var cell = t.size/3.0
	ok(board.last_move_rect().is_equal_approx(Rect2(t.position,cell).grow(-1.4)),"cell rect for a plain move")
	board.last_move_age = 0
	ok(board.last_move_alpha() < .05,"highlight starts from nothing")
	board.last_move_age = Board.LAST_MOVE_POP*.5
	ok(board.last_move_pop() > 1.2,"pop overshoots mid-way")
	board.last_move_age = 1.0
	for clock in [0.0,.65,1.3,1.95]:
		board.clock = clock
		ok(board.last_move_alpha() >= .85,"settled alpha visible at clock %.2f (%.2f)" % [clock,board.last_move_alpha()])
	ok(is_equal_approx(board.last_move_pop(),1.0),"pop settles to scale 1")
	board.reduced_motion = true; board.last_move_age = 0
	ok(board.last_move_alpha() >= .85 and board.last_move_pop() == 1.0,"reduced motion: static, visible")
	board.reduced_motion = false
	# Own move clears it (vs computer only the opponent's move is shown).
	ui._input_beat = 0; ui.play_cell(0,4); ui.thinking = false
	ok(board.last_move.x < 0,"own move not highlighted")
	# A claiming move highlights the whole small board.
	var rules = Rules.new()
	for m in ui.MIDGAME+ui.CLAIM_TAIL: rules.play(m[0],m[1])
	ui.debug_load_position(rules.serialize(),"local")
	var last: Dictionary = ui.game.history.back()
	ok(board.last_move == Vector2i(last.board,last.cell) and board.last_move_whole,"claiming move highlights the whole board")
	ok(board.last_move_rect().is_equal_approx(board.tile_rect(last.board).grow(-board.size.x*.018)),"whole-board rect")
	await frames(1)
