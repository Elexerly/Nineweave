extends Control
## Presentation only. Mouse IGNORE + root input skip leaves legal board taps live.
const R = preload("res://characters/roster.gd")
const Rig = preload("res://characters/rig.gd")
const P = preload("res://ui/paint.gd")
signal finished(kind: String)
var kind: String = ""
var age: float = 0
var active: bool = false
var reduced_motion: bool = false
var frozen: bool = false
var winner_id: String = "vesper_vale"
var loser_id: String = "auric_rex"
var player: int = 1
var region: Rect2
var hero_rect: Rect2
var loser_rect: Rect2
var hero
var loser
var clip_word: String = ""
var _layout: Dictionary
var _claimed_board: int = 4
## True when the pop uses the compact banner variant (Round 3c).
var banner: bool = false
func _ready():
	mouse_filter = Control.MOUSE_FILTER_IGNORE; z_index = 30; visible = false
	hero = Rig.new(); add_child(hero)
	loser = Rig.new(); loser.bust = true; loser.bust_view = LOSER_VIEW; loser.bust_lift = LOSER_LIFT; add_child(loser)
func duration() -> float:
	if reduced_motion: return {"lock_in":.35,"pop":.55,"spotlight":1.0}.get(kind,.5)
	return {"lock_in":.95,"pop":1.2,"spotlight":3.0}.get(kind,1.0)
func show_scene(scene_kind: String, winner: String, rival: String, mark: int, layout: Dictionary, claimed_board: int = 4):
	kind = scene_kind; winner_id = winner; loser_id = rival; player = mark
	age = 0; active = true; visible = true; frozen = false
	_place(layout,claimed_board)
	# No free lane at all: the pop is flavour, so skip it rather than cover play.
	if kind == "pop" and region.size.x <= 0: clear(); return
	hero.configure(winner_id,kind == "pop" and banner); hero.side = player; hero.reduced_motion = reduced_motion
	hero.set_clip({"lock_in":"lock_in","pop":"board_pop","spotlight":"victory"}.get(kind,"idle"))
	loser.configure(loser_id,true); loser.side = 3-player; loser.reduced_motion = reduced_motion; loser.set_clip("defeat")
	loser.visible = kind == "spotlight"
	clip_word = R.get_hero(winner_id).action
	pose()
## Recompute regions for the current scene after a resize; age/clips are untouched.
func relayout(layout: Dictionary):
	if not active: return
	_place(layout,_claimed_board)
	if kind == "pop":
		if region.size.x <= 0: clear(); return
		hero.configure(winner_id,banner)
	pose()
func _place(layout: Dictionary, claimed_board: int):
	_layout = layout; _claimed_board = claimed_board
	var s: Vector2 = layout.size; var seam: Rect2 = layout.hinge
	var safe = Rect2(Vector2(14,14),s-Vector2(28,28))
	if seam.size.x > 0: safe = Rect2(seam.end.x+12,14,s.x-seam.end.x-26,s.y-28)
	region = safe
	if kind == "pop":
		region = pop_region(layout,claimed_board)
		banner = region.size.y < CARD_MIN.y
		if banner:
			# Compact strip: a bust crop on the left, the line beside it.
			var hh = region.size.y-6
			hero_rect = Rect2(region.position+Vector2(8,3),Vector2(minf(hh*.95,region.size.x*.3),hh))
		else: hero_rect = Rect2(region.position+Vector2(2,2),Vector2(region.size.x*.43,region.size.y-4))
	else:
		var portrait = safe.size.x < safe.size.y*.9
		hero_rect = Rect2(safe.position+Vector2(0,44),Vector2(safe.size.x*(.9 if portrait else .6),safe.size.y*(.65 if portrait else .78)))
		if portrait: hero_rect.position.x = safe.get_center().x-hero_rect.size.x*.5
	loser_rect = loser_frame(region)
	hero.position = hero_rect.position; hero.size = hero_rect.size
	loser.position = loser_rect.position; loser.size = loser_rect.size
## Round 3c spotlight inset: the frame has the bust view's aspect, so the clip is the
## frame (no prop slivers at the edge), with headroom for crowns and a caption lane
## that stays clear of the plaque.
const LOSER_VIEW = Vector2(164,186)
const LOSER_LIFT = -5.0
const CAPTION_H = 16.0
static func spotlight_plaque(r: Rect2) -> Rect2:
	if r.size.x < r.size.y*.9: return Rect2(r.position.x+16,r.end.y-r.size.y*.2,r.size.x-32,r.size.y*.15)
	return Rect2(r.position.x+r.size.x*.54,r.end.y-r.size.y*.3,r.size.x*.42,r.size.y*.2)
static func loser_frame(r: Rect2) -> Rect2:
	var aspect = LOSER_VIEW.x/LOSER_VIEW.y
	var landscape = r.size.x >= r.size.y*.9
	var plaque = spotlight_plaque(r)
	var top = r.position.y+52
	var bottom = minf(r.position.y+r.size.y*.67,plaque.position.y-CAPTION_H-14)
	var y0 = top if landscape else maxf(top,r.position.y+r.size.y*.38)
	var h = minf(r.size.y*(.34 if landscape else .29),bottom-y0)
	var w = minf(h*aspect,r.size.x*.26); h = w/aspect
	if landscape: return Rect2(plaque.end.x-w,bottom-h,w,h)
	return Rect2(r.end.x-r.size.x*.03-w,y0,w,h)
static func loser_caption(frame: Rect2) -> Rect2:
	return Rect2(frame.position.x-20,frame.end.y+5,frame.size.x+40,CAPTION_H)
## Round 3c: the pop lives in a free lane. It never covers the board, the fold, a live
## hero (corner bust, Duo panel or scorecard figure), the info heading, the minimap,
## the controls or the message lane. Without room for the card it becomes a banner.
const POP_GAP = 6.0
const CARD_MIN = Vector2(120,72)
const BANNER_MIN = Vector2(120,28)
const BANNER_MAX = Vector2(280,56)
## Everything the pop must leave visible, keyed for tests and diagnostics.
static func protected_rects(layout: Dictionary) -> Dictionary:
	var b: Rect2 = layout.board
	var result = {"board":b}
	if layout.hinge.size.x > 0: result.hinge = layout.hinge
	for key in ["players","turn","info","controls","message","minimap","stats","character","history","hero_player","hero_opponent"]:
		if layout.has(key) and layout[key].size.x > 0 and layout[key].size.y > 0: result[key] = layout[key]
	var hdr: Rect2 = layout.header; var hb = 52.0 if layout.mode == "landscape" else 44.0
	result.home = Rect2(hdr.position,Vector2(hb,hb)); result.settings = Rect2(hdr.end.x-hb,hdr.position.y,hb,hb)
	# The active scorecard's crown, the callout lip above the board and the X/O turn
	# tiles that overhang the phone control row.
	result.crown = Rect2(layout.players.position.x,layout.players.position.y-10,layout.players.size.x,10)
	result.callout = Rect2(b.position.x,b.position.y-14,b.size.x,14)
	if layout.mode in ["phone_portrait","tablet_portrait"]:
		var cr: Rect2 = layout.controls
		result.tiles = Rect2(cr.position.x,cr.position.y-4,cr.size.x,minf(cr.size.y+8,84))
	return result
static func pop_region(layout: Dictionary, claimed_board: int) -> Rect2:
	var b: Rect2 = layout.board; var s: Vector2 = layout.size
	var w = minf(b.size.x*.44,230); var h = minf(126,w*.65)
	var view = Rect2(Vector2(8,8),s-Vector2(16,16))
	var blocks: Array = []
	for r in protected_rects(layout).values(): blocks.append(r.grow(POP_GAP))
	var anchor = b.position+b.size*Vector2((claimed_board%3+.5)/3.0,(claimed_board/3+.5)/3.0)
	var best = Rect2(); var best_score = -1.0
	for f in free_rects(view,blocks,BANNER_MIN):
		for card in [true,false]:
			var fit = Vector2(minf(w,f.size.x),minf(h,f.size.y)) if card else Vector2(minf(BANNER_MAX.x,f.size.x),minf(BANNER_MAX.y,f.size.y))
			var low = CARD_MIN if card else BANNER_MIN
			if fit.x < low.x or fit.y < low.y: continue
			var r = Rect2((anchor-fit*.5).clamp(f.position,f.end-fit),fit)
			# A card always beats a banner; then the biggest; then the nearest to the claim.
			var score = (1e7 if card else 0.0)+fit.x*fit.y-r.get_center().distance_to(anchor)*.01
			if score > best_score: best = r; best_score = score
	return best
## Empty rectangles between the blocks (one per column band and vertical gap).
static func free_rects(view: Rect2, blocks: Array, min_size: Vector2) -> Array:
	var xs: Array = [view.position.x,view.end.x]
	for o in blocks:
		for x in [o.position.x,o.end.x]:
			if x > view.position.x and x < view.end.x and not xs.has(x): xs.append(x)
	xs.sort()
	var out: Array = []
	for i in range(xs.size()):
		for j in range(i+1,xs.size()):
			var xl: float = xs[i]; var xr: float = xs[j]
			if xr-xl < min_size.x: continue
			var spans: Array = []
			for o in blocks:
				if o.position.x < xr and o.end.x > xl: spans.append(Vector2(o.position.y,o.end.y))
			spans.sort()
			var y = view.position.y
			for span in spans:
				if span.x-y >= min_size.y: out.append(Rect2(xl,y,xr-xl,minf(span.x,view.end.y)-y))
				y = maxf(y,span.y)
			if view.end.y-y >= min_size.y: out.append(Rect2(xl,y,xr-xl,view.end.y-y))
	return out
func advance(delta: float):
	if not active or frozen: return
	age += delta
	if age >= duration(): complete(); return
	pose()
func skip() -> bool:
	if not active or age < .2: return false
	complete(); return true
func complete():
	if not active: return
	var was = kind; active = false; visible = false; finished.emit(was)
func clear(): active = false; visible = false; kind = ""
func pose():
	if not active: return
	var t = age/duration(); var ease = 1-pow(1-clampf(age/.26,0,1),3)
	modulate.a = minf(1,age/.08)*(1-smoothstep(.82,1.0,t))
	var move = Vector2.ZERO if reduced_motion else Vector2((1-ease)*region.size.x*.12,0) if kind == "pop" else Vector2((1-ease)*-region.size.x*.22,sin(ease*PI)*-6)
	hero.position = hero_rect.position+move
	hero.pivot_offset = hero.size*.5
	hero.scale = Vector2.ONE*(1 if reduced_motion or kind == "pop" else 1+sin(ease*PI)*.07)
	queue_redraw()
func _draw():
	if not active: return
	var s: Vector2 = _layout.size; var col = P.mark_color(player); var r = region
	if kind != "pop": draw_rect(Rect2(Vector2.ZERO,s),Color(.006,.018,.045,.95))
	var e = 1-pow(1-clampf(age/.24,0,1),3)
	var panel = P.polygon(r,minf(18,r.size.y*.13))
	panel[0].x += minf(10,r.size.x*.04); panel[3].x -= 5
	draw_colored_polygon(panel,Color("0b1b34"))
	draw_polyline(panel+PackedVector2Array([panel[0]]),P.GOLD_DARK,8,true)
	draw_polyline(panel+PackedVector2Array([panel[0]]),P.GOLD,3,true)
	var origin = hero_rect.get_center()
	if kind != "pop": P.halo(self,origin,hero_rect.size.y*.8,Color(col,.24))
	var rays = 6 if reduced_motion else 22
	for i in range(rays):
		var angle = i*TAU/rays+.15
		var a = origin+Vector2.from_angle(angle)*40
		var b = origin+Vector2.from_angle(angle)*(r.size.length()*.7)
		# Clamp speed strokes inside the safe panel. Nothing crosses a fold.
		a = a.clamp(r.position+Vector2(8,8),r.end-Vector2(8,8)); b = b.clamp(r.position+Vector2(8,8),r.end-Vector2(8,8))
		draw_line(a,b,Color(col,.12*e),1+i%3,true)
	# Gold dot texture down the left edge; rows stop inside short banners.
	for i in range(3*clampi(int((r.size.y-16)/9),0,6)):
		var x = r.position.x+8+(i%3)*5; var y = r.position.y+12+(i/3)*9
		draw_circle(Vector2(x,y),1.4,Color(P.GOLD,.26))
	var h = R.get_hero(winner_id)
	if kind == "pop" and banner:
		var tx = hero_rect.end.x+6
		var tr = Rect2(tx,r.position.y+3,r.end.x-tx-10,r.size.y-6)
		var top = Rect2(tr.position,Vector2(tr.size.x,tr.size.y*.56)); var low = Rect2(tr.position+Vector2(0,tr.size.y*.54),Vector2(tr.size.x,tr.size.y*.46))
		P.text(self,clip_word,top,P.fit_box(clip_word,top,18,P.DISPLAY),P.PALE,P.DISPLAY,HORIZONTAL_ALIGNMENT_CENTER,.5)
		P.text(self,str(h.pop),low,P.fit_box(str(h.pop),low,13),P.WHITE)
	elif kind == "pop":
		var tr = Rect2(r.position+Vector2(r.size.x*.43,6),Vector2(r.size.x*.53,r.size.y-12))
		P.text(self,clip_word,Rect2(tr.position,Vector2(tr.size.x,tr.size.y*.42)),20,P.PALE,P.DISPLAY,HORIZONTAL_ALIGNMENT_CENTER,.5)
		var words = str(h.pop).split(" "); var half = int(ceil(words.size()*.5))
		P.text(self," ".join(words.slice(0,half)),Rect2(tr.position+Vector2(0,tr.size.y*.44),Vector2(tr.size.x,tr.size.y*.25)),13,P.WHITE)
		P.text(self," ".join(words.slice(half)),Rect2(tr.position+Vector2(0,tr.size.y*.67),Vector2(tr.size.x,tr.size.y*.25)),13,P.WHITE)
	else:
		P.text(self,"LEGEND LOCKED" if kind == "lock_in" else "THE WEAVE IS YOURS",Rect2(r.position+Vector2(14,10),Vector2(r.size.x-28,38)),27,P.PALE,P.SERIF)
		var plaque = spotlight_plaque(r)
		P.panel(self,plaque,false,1,true)
		P.text(self,h.name.to_upper(),Rect2(plaque.position+Vector2(6,2),Vector2(plaque.size.x-12,plaque.size.y*.48)),28,P.PALE,P.SERIF)
		var line = h.pop if kind == "lock_in" else h.victory
		# Split long lines into two rows instead of shrinking them to unreadable type.
		var words = str(line).split(" "); var half = int(ceil(words.size()*.5))
		P.text(self," ".join(words.slice(0,half)),Rect2(plaque.position+Vector2(6,plaque.size.y*.46),Vector2(plaque.size.x-12,plaque.size.y*.23)),18,P.WHITE)
		P.text(self," ".join(words.slice(half)),Rect2(plaque.position+Vector2(6,plaque.size.y*.69),Vector2(plaque.size.x-12,plaque.size.y*.23)),18,P.WHITE)
		if kind == "spotlight":
			P.outline(self,loser_rect.grow(3),P.GOLD,2)
			P.text(self,"A THREAD UNRAVELS",loser_caption(loser_rect),12,P.MUTED)
		P.text(self,"TAP TO CONTINUE" if age >= .2 else "",Rect2(r.position.x+12,r.end.y-30,r.size.x-24,20),12,P.GOLD)
