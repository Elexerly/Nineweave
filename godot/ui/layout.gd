class_name NineweaveLayout
extends RefCounted
## Pure layout, in logical CSS-like units. No scene/window dependency.
static func logical_size(physical: Vector2) -> Vector2:
	# Capture at the measured Duo's 3x physical size; same composition, crisp fonts.
	if physical.x >= 2400 and physical.y >= 1400 and physical.x/physical.y < 1.8:
		return physical/3.0
	return physical
static func mode_for(s: Vector2) -> String:
	var ratio = s.x/s.y
	if s.x > s.y:
		if s.y < 450 or ratio > 1.9: return "phone_landscape" if s.y < 500 else "landscape"
		if s.x >= 700 and s.x <= 1200 and s.y >= 480 and s.y <= 740 and ratio >= 1.02 and ratio <= 1.75: return "duo_landscape"
		return "landscape"
	if s.x >= 600 and ratio >= .78 and ratio <= .95: return "duo_portrait"
	if s.x >= 600: return "tablet_portrait"
	return "phone_portrait"
static func compute(physical: Vector2, hinge: Rect2 = Rect2()) -> Dictionary:
	var s = logical_size(physical)
	var scale = physical.x/s.x
	var seam = Rect2(hinge.position/scale,hinge.size/scale)
	var mode = mode_for(s)
	# An explicit vertical fold always selects a safe split composition.
	if seam.size.x > 0: mode = "duo_landscape"
	var r = {"mode":mode,"size":s,"scale":scale,"touch":44.0,"hinge":seam}
	var w = s.x; var h = s.y; var margin = 12.0
	if mode == "phone_portrait" or mode == "tablet_portrait":
		var board_size = minf(w-24,h-318)
		if mode == "tablet_portrait": board_size = minf(w-56,h-332)
		var by = 174+clampf((h-w-304)*.16,0,30)
		r.header = Rect2(12,12,w-24,44)
		r.players = Rect2(18,66,w-36,60)
		r.turn = Rect2(w*.28,134,w*.44,30)
		r.board = Rect2((w-board_size)/2,by,board_size,board_size)
		r.info = Rect2(20,by+board_size+12,w-40,50)
		r.controls = Rect2(20,minf(h-74,by+board_size+78),w-40,60)
	elif mode == "duo_portrait":
		var bs = minf(w-32,h-304)
		r.header = Rect2(16,12,w-32,44)
		r.players = Rect2(32,66,w-64,54)
		r.board = Rect2((w-bs)/2,132,bs,bs)
		var y = 144+bs
		r.turn = Rect2(16,y,176,36)
		r.info = Rect2(204,y,w-220,36)
		r.minimap = Rect2(16,y+44,88,88)
		r.character = Rect2(116,y+44,w-340,88)
		r.stats = Rect2(w-212,y+44,196,30)
		r.controls = Rect2(w-212,y+82,196,50)
	elif mode == "duo_landscape" or mode == "phone_landscape":
		var split = h+2 if mode == "phone_landscape" else w*.52
		var board_end = split-12
		var panel_start = split+4
		if seam.size.x > 0:
			board_end = seam.position.x-12
			panel_start = seam.end.x+12
		var bs = minf(h-28,board_end-16)
		r.board = Rect2(14,(h-bs)/2,bs,bs)
		var pw = w-panel_start-14
		var x = panel_start
		r.header = Rect2(x,12,pw,44)
		if mode == "phone_landscape":
			r.players = Rect2(x,64,pw,60)
			r.turn = Rect2(x,134,pw,36)
			r.info = Rect2(x,180,pw,50)
			r.controls = Rect2(x,h-66,pw,52)
		else:
			r.players = Rect2(x,68,pw,76)
			r.turn = Rect2(x,156,pw,42)
			r.stats = Rect2(x,208,pw,36)
			var mh = clampf(h-388,72,132)
			mh = minf(mh,104)
			r.character = Rect2(x,256,pw*.46,h-338)
			r.minimap = Rect2(x+pw*.5,256,mh,mh)
			r.info = Rect2(x+pw*.5,264+mh,pw*.5,44)
			r.controls = Rect2(x,h-70,pw,56)
	else:
		# Tablet composition from the art: tall player cards fill the left column, the board
		# sits centre, and the right panel (header, Turn, Active Board card, controls) fills its column.
		var left = clampf(w*.165,130,300)
		var right = clampf(w*.23,210,380)
		var bs = minf(h-64,w-left-right-80)
		var bx = left+34+(w-left-right-80-bs)*.5
		r.board = Rect2(bx,(h-bs)/2,bs,bs)
		r.players = Rect2(20,h*.08,left-12,h*.84)
		var rx = w-right+4; var rw = right-24
		r.header = Rect2(rx,24,rw,52)
		r.turn = Rect2(rx,92,rw,clampf(h*.075,48,76))
		var ch = clampf(h*.08,56,80)
		r.controls = Rect2(rx,h-24-ch,rw,ch)
		var iy = r.turn.end.y+16
		r.info = Rect2(rx,iy,rw,r.controls.position.y-16-iy)
		if seam.size.x > 0:
			# Also safe for a wide external display with an explicit seam.
			var panel_left = seam.end.x+16
			bs = minf(h-32,seam.position.x-32)
			r.board = Rect2(16,(h-bs)/2,bs,bs)
			r.players = Rect2(panel_left,80,w-panel_left-16,80)
			r.header = Rect2(panel_left,16,w-panel_left-16,44)
			r.turn = Rect2(panel_left,176,w-panel_left-16,44)
			r.info = Rect2(panel_left,236,w-panel_left-16,180)
			r.controls = Rect2(panel_left,h-80,w-panel_left-16,56)
	# Short phone landscape uses height first; 568x320 still keeps 44px controls.
	if mode == "phone_landscape" and h < 360:
		r.players = Rect2(r.players.position.x,62,r.players.size.x,48)
		r.turn = Rect2(r.turn.position.x,118,r.turn.size.x,30)
		r.info = Rect2(r.info.position.x,156,r.info.size.x,44)
	# Corner overlays never enter the board, the fold, or any HUD rect (Round 3b).
	# A side whose corner has no readable space gets an empty rect: main then makes
	# that side's scorecard figure the live reacting character instead.
	r.message = Rect2(16,h-20,w-32,18)
	# Short phones put controls at h-74; keep the message lane below them, never over the buttons.
	if r.message.position.y < r.controls.end.y+1:
		r.message = Rect2(16,r.controls.end.y+1,w-32,maxf(10,h-r.controls.end.y-2))
	var own = Rect2(); var rival = Rect2()
	r.hero_player_host = ""
	if mode == "duo_portrait":
		r.minimap.position.x = 116
		r.character = Rect2(216,r.character.position.y,maxf(40,w-440),88)
		var oh = minf(104,r.message.position.y-6-r.minimap.position.y)
		if oh >= MIN_CORNER: own = Rect2(12,r.minimap.position.y,92,oh)
	elif mode in ["phone_portrait","tablet_portrait"]:
		# Mirrored busts in the strip under the control row, above the message lane.
		var top = r.controls.end.y+10
		var oh = minf(124,r.message.position.y-6-top)
		var ow = minf(120,w*.29)
		if oh >= MIN_CORNER:
			own = Rect2(8,r.message.position.y-6-oh,ow,oh)
			rival = Rect2(w-8-ow,own.position.y,ow,oh)
	elif mode == "duo_landscape":
		# The Duo character panel is the player's live figure; the strip under the
		# board is only ~50 px, too small to read. The message uses that strip.
		r.hero_player_host = "character"
		own = Rect2(r.character.position+Vector2(4,24),r.character.size-Vector2(8,28))
		if h-r.board.end.y-14 >= 24: r.message = Rect2(r.board.position.x,r.board.end.y+6,r.board.size.x,18)
		else: r.message = Rect2(r.controls.position.x,r.controls.position.y-22,r.controls.size.x,18)
	elif mode == "phone_landscape":
		# Height-filling board: mirrored busts in the side deck between info and the message lane.
		r.message = Rect2(r.controls.position.x,r.controls.position.y-22,r.controls.size.x,18)
		var top = r.info.end.y+6
		var oh = r.message.position.y-4-top
		var ow = minf(102,r.controls.size.x*.34)
		if oh >= MIN_CORNER:
			oh = minf(oh,124)
			own = Rect2(r.controls.position.x,top,ow,oh)
			rival = Rect2(r.controls.end.x-ow,top,ow,oh)
	# Tablet/desktop landscape: the tall scorecards already hold full figures; they react live.
	r.hero_player = own; r.hero_opponent = rival
	return r
## Below this height a bust no longer reads as a character.
const MIN_CORNER = 56.0
## HUD rects a corner character must never cover (board excluded; checked separately).
static func hud_rects(layout: Dictionary) -> Dictionary:
	var result = major_rects(layout)
	if layout.has("message"): result["message"] = layout.message
	return result
static func major_rects(layout: Dictionary) -> Dictionary:
	var result = {}
	for key in ["header","players","turn","board","info","controls","stats","minimap","history","character"]:
		if layout.has(key): result[key] = layout[key]
	return result
