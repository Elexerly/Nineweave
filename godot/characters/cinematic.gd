extends Control
## Claim pops ignore input. Full-screen match cards shield the game and support guarded skip.
const R = preload("res://characters/roster.gd")
const Rig = preload("res://characters/art.gd")
const P = preload("res://ui/paint.gd")
const Motion = preload("res://characters/cinematic_motion.gd")
const Sway = preload("res://characters/victory_sway.gdshader")
const VideoOverlay = preload("res://characters/hero_video_overlay.gd")
const GoldLabel = preload("res://ui/gold_label.gd")
const Badge = preload("res://characters/loser_badge.gdshader")
signal finished(kind: String)
signal buttons_ready
var video_source
var video_overlay
var buttons_shown: bool = false
var combined_result: bool = false
var result_title: String = "VICTORY"
var result_detail: String = ""
var winner_name: String = "YOU"
var loser_name: String = "COMPUTER"
var result_score: String = ""
var front: Control
var _gold_result_title: Label
var _result_copy_key: Array = []
var _result_copy_rows: Array = []
var _sway: ShaderMaterial
var _badge: ShaderMaterial
var _dots_cool: ArrayMesh
var _dots_warm: ArrayMesh
var _letters: Array = []
var arrangement: String = "vertical"
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
	front = Control.new(); front.mouse_filter = Control.MOUSE_FILTER_IGNORE; front.draw.connect(_draw_front); add_child(front)
	video_overlay = VideoOverlay.new(); video_overlay.source = video_source; front.add_child(video_overlay)
	video_overlay.finished.connect(_video_finished)
	_gold_result_title = GoldLabel.new(); front.add_child(_gold_result_title); _gold_result_title.hide()
func video_playing() -> bool: return is_instance_valid(video_overlay) and video_overlay.visible
func duration() -> float:
	# Videos end on decoder signals (the longer intro wins), never the old 3s clock.
	if video_playing() and video_overlay.active: return INF
	if kind in ["versus","spotlight","draw"]:
		if reduced_motion: return .65 if kind == "versus" else 1.0
		return Motion.VERSUS_SECONDS if kind == "versus" else Motion.RESULT_SECONDS
	if reduced_motion: return {"lock_in":.35,"pop":.55,"spotlight":1.0}.get(kind,.5)
	return {"lock_in":.95,"pop":1.2,"spotlight":3.0}.get(kind,1.0)
func show_scene(scene_kind: String, winner: String, rival: String, mark: int, layout: Dictionary, claimed_board: int = 4):
	video_overlay.clear()
	combined_result = scene_kind == "spotlight"
	hero.visible = true
	mouse_filter = Control.MOUSE_FILTER_STOP if scene_kind in ["versus","spotlight","draw"] else Control.MOUSE_FILTER_IGNORE
	kind = scene_kind; winner_id = winner; loser_id = rival; player = mark
	front.visible = kind in ["versus","spotlight","draw"]
	age = 0; active = true; visible = true; frozen = false; buttons_shown = false; modulate.a = 1
	position = Vector2.ZERO; scale = Vector2.ONE; pivot_offset = Vector2.ZERO
	_place(layout,claimed_board)
	# No free lane at all: the pop is flavour, so skip it rather than cover play.
	if kind == "pop" and region.size.x <= 0: clear(); return
	hero.art_key = "versus" if kind == "versus" else ("victory" if kind == "spotlight" else ("head_neutral" if kind == "draw" else ""))
	hero.configure(winner_id,kind in ["pop","draw"]); hero.side = player; hero.reduced_motion = reduced_motion
	hero.set_clip({"lock_in":"lock_in","pop":"board_pop","spotlight":"victory"}.get(kind,"idle"))
	loser.art_key = "versus" if kind == "versus" else "head_neutral"
	hero.fit_height = kind == "versus"; loser.fit_height = kind == "versus"
	loser.configure(loser_id,kind != "versus"); loser.side = 3-player; loser.reduced_motion = reduced_motion; loser.set_clip("defeat")
	loser.visible = kind in ["versus","draw","spotlight"]
	hero.frozen = kind in ["versus","spotlight","draw"]; loser.frozen = hero.frozen
	hero.material = null
	loser.material = null
	if kind == "spotlight":
		if _sway == null: _sway = ShaderMaterial.new(); _sway.shader = Sway
		hero.material = _sway
		if _badge == null: _badge = ShaderMaterial.new(); _badge.shader = Badge
		loser.material = _badge
	clip_word = R.get_hero(winner_id).action
	pose()
	video_overlay.source = video_source
	video_overlay.display_lane = combined_geometry(region.size).hero if combined_result else Rect2()
	if not reduced_motion: video_overlay.begin(kind,winner_id,loser_id,player,region.size)
	if combined_result:
		buttons_shown = true; buttons_ready.emit(); pose()
## Recompute regions for the current scene after a resize; age/clips are untouched.
func relayout(layout: Dictionary):
	if not visible: return
	_place(layout,_claimed_board)
	if kind == "pop":
		if region.size.x <= 0: clear(); return
		hero.configure(winner_id,true); hero.expression = "smug"; hero.refresh_texture()
	pose()
	if video_playing():
		video_overlay.display_lane = combined_geometry(region.size).hero if combined_result else Rect2()
		video_overlay.relayout(region.size)
func _place(layout: Dictionary, claimed_board: int):
	_layout = layout; _claimed_board = claimed_board
	var s: Vector2 = layout.size; var seam: Rect2 = layout.hinge
	if kind in ["versus","spotlight","draw"]:
		region = Rect2(Vector2.ZERO,s)
		arrangement = "vertical" if s.x < s.y else "horizontal"
		var g = combined_geometry(s) if combined_result else card_geometry(s,kind)
		hero_rect = g.hero; loser_rect = g.rival
		hero.position = hero_rect.position; hero.size = hero_rect.size
		loser.position = loser_rect.position; loser.size = loser_rect.size
		loser.facing = -1 if kind in ["versus","draw"] else 1
		front.position = Vector2.ZERO; front.size = s
		_build_halftone(s)
		if not combined_result: _build_letters(g)
		else: _letters.clear()
		_refresh_gold_result_title()
		return
	var safe = Rect2(Vector2(14,14),s-Vector2(28,28))
	if seam.size.x > 0: safe = Rect2(seam.end.x+12,14,s.x-seam.end.x-26,s.y-28)
	region = safe
	_refresh_gold_result_title()
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
	if reduced_motion and video_playing(): video_overlay.clear(); age = 0; pose()
	age += delta
	if video_playing(): return
	if kind in ["spotlight","draw"] and age >= buttons_at() and not buttons_shown:
		buttons_shown = true; buttons_ready.emit()
	if age >= duration(): complete(); return
	pose()
func skip() -> bool:
	if not active or age < (.6 if kind == "versus" else (.8 if kind in ["spotlight","draw"] else .2)): return false
	complete(); return true
func _video_finished():
	# Godot retains the last decoded texture when a non-looping stream finishes.
	# Keep that frame in the result lane until navigation, rather than swapping art.
	complete(video_overlay.holds_completed_result())
func complete(preserve_video: bool = false):
	if not active: return
	if not preserve_video: video_overlay.clear()
	var was = kind; age = Motion.RESULT_SECONDS if preserve_video else duration(); active = false
	visible = kind in ["spotlight","draw"]
	if visible: buttons_shown = true; pose()
	finished.emit(was)
func clear():
	if is_instance_valid(video_overlay): video_overlay.clear()
	combined_result = false; active = false; visible = false; kind = ""; buttons_shown = false; mouse_filter = Control.MOUSE_FILTER_IGNORE
	if is_instance_valid(_gold_result_title): _gold_result_title.hide()
	position = Vector2.ZERO; scale = Vector2.ONE; modulate.a = 1
func buttons_at() -> float: return .25 if reduced_motion else Motion.BUTTONS_AT
func buttons_progress() -> float:
	if combined_result: return 1.0
	return clampf((age-buttons_at())/(.15 if reduced_motion else .28),0,1)
## Tool-only seek. Never emits controller signals or advances the match/AI.
func seek(seconds: float):
	# Analytic legacy captures remain stable; live results use the combined card.
	if combined_result:
		combined_result = false; hero.visible = true; loser.visible = true; _place(_layout,_claimed_board)
	# Analytic capture always uses the original code animation, even after a live video.
	if is_instance_valid(video_overlay): video_overlay.clear()
	age = clampf(seconds,0,duration()); frozen = true; active = age < duration()
	visible = kind != "versus" or active
	buttons_shown = kind in ["spotlight","draw"] and age >= buttons_at()
	pose()
func winner_accent() -> Color: return P.mark_color(player)
func score_font_size() -> int: return clampi(int(minf(region.size.x,region.size.y)*.027),16,28)
func letter_count(wins: bool = false, at: float = -1) -> int:
	var value = "WINS!" if wins else ("DRAW" if kind == "draw" else winner_name.to_upper())
	var t = age if at < 0 else at
	var start = Motion.letter_start(winner_name.length(),wins,reduced_motion)
	if reduced_motion: return value.length() if t >= start else 0
	return clampi(int(floor((t-start)/Motion.LETTER_STEP))+1,0,value.length())
## This is the actual opaque viewport cover used by the draw path, including t=0.
func versus_cover_rect() -> Rect2:
	return region if kind == "versus" and visible and age < minf(Motion.EXIT_AT,duration()) else Rect2()
func versus_cover_alpha() -> float:
	return 1.0 if versus_cover_rect().has_area() else 0.0
func loser_badge_rect() -> Rect2:
	return Rect2(loser.position,loser.size)
func pose():
	if combined_result:
		position = Vector2.ZERO; scale = Vector2.ONE; modulate.a = 1; front.modulate.a = 1
		hero.position = hero_rect.position; hero.size = hero_rect.size; hero.scale = Vector2.ONE; hero.modulate.a = 1
		hero.visible = not video_playing(); loser.visible = false
		front.queue_redraw(); queue_redraw(); return
	if video_playing():
		position = Vector2.ZERO; scale = Vector2.ONE; modulate.a = 1
		return
	if kind in ["versus","spotlight","draw"]:
		var s = region.size
		pivot_offset = s*.5
		position = Motion.shake(age,reduced_motion) if kind == "versus" else Vector2.ZERO
		scale = Vector2.ONE*(1.0 if reduced_motion or kind != "versus" else 1.0+.06*Motion.out_cubic(age/2.65))
		modulate.a = clampf(age/.16,0,1) if reduced_motion and kind != "versus" else 1.0
		hero.pivot_offset = Vector2(hero.size.x*.5,hero.size.y)
		loser.pivot_offset = loser.size*.5; loser.rotation = 0
		hero.modulate.a = 1; loser.modulate.a = 1
		if kind == "versus":
			hero.position = hero_rect.position+Motion.actor_offset(s,age,false,reduced_motion)
			loser.position = loser_rect.position+Motion.actor_offset(s,age,true,reduced_motion)
			hero.scale = Motion.breath(age,false,reduced_motion); loser.scale = Motion.breath(age,true,reduced_motion)
			front.modulate.a = Motion.exit_type_alpha(age) if not reduced_motion else 1.0-clampf((age-.5)/.15,0,1)
		elif kind == "draw":
			var e = 1.0-Motion.back(age/.4)
			var bump = sin(clampf((age-.3)/.20,0,1)*PI)*s.x*.025
			hero.position = hero_rect.position+Vector2(-s.x*e-bump,0) if not reduced_motion else hero_rect.position
			loser.position = loser_rect.position+Vector2(s.x*e+bump,0) if not reduced_motion else loser_rect.position
			hero.scale = Vector2.ONE; loser.scale = Vector2.ONE; front.modulate.a = 1
		else:
			var leap = clampf(age/Motion.CLASH,0,1)
			var e = 1.0-Motion.out_cubic(leap)
			hero.position = hero_rect.position+Vector2(-s.x*.13*sin(leap*PI),s.y*.9*e-s.y*.13*sin(leap*PI)) if not reduced_motion else hero_rect.position
			if not reduced_motion and age >= .52: hero.position.y += sin((age-.52)*2.3)*3.5
			var landing = sin(clampf((age-Motion.CLASH)/.18,0,1)*PI)*.12 if not reduced_motion else 0.0
			hero.scale = Vector2(1+landing,1-landing)*Motion.breath(age,false,reduced_motion)
			var stagger = Motion.out_cubic((age-.58)/.6)
			var hit = clampf((age-.4)/.18,0,1)
			var shake_x = sin(hit*PI*7)*(1.0-hit)*loser_rect.size.x*.07 if age >= .4 else 0.0
			loser.position = loser_rect.position+Vector2(shake_x,stagger*loser_rect.size.y*.07) if not reduced_motion else loser_rect.position
			loser.rotation = stagger*.18 if not reduced_motion else 0.0
			loser.scale = Vector2.ONE
			loser.modulate.a = clampf((age-.24)/.12,0,1) if not reduced_motion else 1.0
			var face = "head_pout" if reduced_motion or age >= 1.5 or age >= .58 and age < 1.0 else ("head_panic" if age >= 1.0 else "head_neutral")
			if loser.art_key != face: loser.art_key = face; loser.expression = face.trim_prefix("head_"); loser.refresh_texture()
			_sway.set_shader_parameter("cinematic_time",age)
			_sway.set_shader_parameter("sway_pixels",0.0 if reduced_motion else minf(4,s.x*.006))
			front.modulate.a = 1
		front.queue_redraw(); queue_redraw(); return
	if not active: return
	var t = age/duration(); var ease = 1-pow(1-clampf(age/.26,0,1),3)
	modulate.a = minf(1,age/.08)*(1-smoothstep(.82,1.0,t))
	var move = Vector2.ZERO if reduced_motion else Vector2((1-ease)*region.size.x*.12,0) if kind == "pop" else Vector2((1-ease)*-region.size.x*.22,sin(ease*PI)*-6)
	hero.position = hero_rect.position+move
	hero.pivot_offset = hero.size*.5
	hero.scale = Vector2.ONE*(1 if reduced_motion or kind == "pop" else 1+sin(ease*PI)*.07)
	queue_redraw()
func _draw():
	if combined_result and visible:
		draw_rect(region,Color("071222"))
		preload("res://ui/readability.gd").draw_panel(self,Rect2(region.size.x*.48,0,region.size.x*.52,region.size.y))
		return
	if kind in ["versus","spotlight","draw"] and visible:
		_draw_card_background(); return
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
		P.text(self,clip_word,Rect2(tr.position,Vector2(tr.size.x,tr.size.y*.42)),P.fit_box(clip_word,Rect2(Vector2.ZERO,Vector2(tr.size.x,tr.size.y*.42)),20,P.DISPLAY),P.PALE,P.DISPLAY,HORIZONTAL_ALIGNMENT_CENTER,.5)
		var words = str(h.pop).split(" "); var half = int(ceil(words.size()*.5))
		P.text(self," ".join(words.slice(0,half)),Rect2(tr.position+Vector2(0,tr.size.y*.44),Vector2(tr.size.x,tr.size.y*.25)),13,P.WHITE)
		P.text(self," ".join(words.slice(half)),Rect2(tr.position+Vector2(0,tr.size.y*.67),Vector2(tr.size.x,tr.size.y*.25)),13,P.WHITE)
	else:
		P.text(self,"LEGEND LOCKED" if kind == "lock_in" else "THE WEAVE IS YOURS",Rect2(r.position+Vector2(14,10),Vector2(r.size.x-28,38)),27,P.PALE,P.SERIF)
		var plaque = spotlight_plaque(r)
		P.panel(self,plaque,false,1,true)
		var name_box = Rect2(plaque.position+Vector2(6,2),Vector2(plaque.size.x-12,plaque.size.y*.48))
		P.text(self,h.name.to_upper(),name_box,P.fit_box(h.name.to_upper(),name_box,28,P.SERIF),P.PALE,P.SERIF)
		var line = h.pop if kind == "lock_in" else h.victory
		# Split long lines into two rows instead of shrinking them to unreadable type.
		var words = str(line).split(" "); var half = int(ceil(words.size()*.5))
		P.text(self," ".join(words.slice(0,half)),Rect2(plaque.position+Vector2(6,plaque.size.y*.46),Vector2(plaque.size.x-12,plaque.size.y*.23)),18,P.WHITE)
		P.text(self," ".join(words.slice(half)),Rect2(plaque.position+Vector2(6,plaque.size.y*.69),Vector2(plaque.size.x-12,plaque.size.y*.23)),18,P.WHITE)
		if kind == "spotlight":
			P.outline(self,loser_rect.grow(3),P.GOLD,2)
			P.text(self,"A THREAD UNRAVELS",loser_caption(loser_rect),12,P.MUTED)
		P.text(self,"TAP TO CONTINUE" if age >= .2 else "",Rect2(r.position.x+12,r.end.y-30,r.size.x-24,20),12,P.GOLD)

## Comic composition in normalized screen units. No board layout is touched.
static func card_geometry(s: Vector2, scene_kind: String) -> Dictionary:
	var portrait = s.x < s.y
	var g = {"hero":Rect2(),"rival":Rect2()}
	if scene_kind == "versus":
		if portrait:
			g.hero = Rect2(-s.x*.02,s.y*.52,s.x*.80,s.y*.45)
			g.rival = Rect2(s.x*.025,s.y*.085,s.x*.96,s.y*.41)
			g.player_plate = Rect2(s.x*.43,s.y*.90,s.x*.52,s.y*.065)
			g.rival_plate = Rect2(s.x*.07,s.y*.04,s.x*.52,s.y*.065)
		else:
			g.hero = Rect2(0,s.y*.02,s.x*.47,s.y*.96)
			g.rival = Rect2(s.x*.51,s.y*.025,s.x*.53,s.y*.96)
			g.player_plate = Rect2(s.x*.04,s.y*.82,s.x*.30,s.y*.125)
			g.rival_plate = Rect2(s.x*.68,s.y*.82,s.x*.29,s.y*.125)
	else:
		if portrait:
			g.hero = Rect2(s.x*.10,s.y*.10,s.x*.80,s.y*.62)
			g.name = Rect2(s.x*.06,s.y*.69,s.x*.88,s.y*.09)
			g.wins = Rect2(s.x*.10,s.y*.77,s.x*.80,s.y*.075)
			g.subtitle = Rect2(s.x*.08,s.y*.847,s.x*.84,s.y*.035)
			g.again = Rect2(s.x*.08,s.y*.919,s.x*.40,maxf(44,s.y*.05))
			g.menu = Rect2(s.x*.55,s.y*.919,s.x*.39,maxf(44,s.y*.05))
		else:
			g.hero = Rect2(s.x*.06,s.y*.045,s.x*.39,s.y*.92)
			g.name = Rect2(s.x*.49,s.y*.19,s.x*.46,s.y*.19)
			g.wins = Rect2(s.x*.53,s.y*.395,s.x*.38,s.y*.18)
			g.subtitle = Rect2(s.x*.51,s.y*.61,s.x*.42,s.y*.055)
			g.again = Rect2(s.x*.55,s.y*.79,s.x*.18,maxf(44,s.y*.09))
			g.menu = Rect2(s.x*.76,s.y*.79,s.x*.19,maxf(44,s.y*.09))
		var head = clampf(s.x*88.0/390.0,84,136) if portrait else clampf(minf(s.x*.12,s.y*.19),80,180)
		g.rival = Rect2(s.x-head-18,s.y*.46,head,head) if portrait else Rect2(s.x*.055,s.y*.72,head,head)
		if scene_kind == "draw":
			g.hero = Rect2(s.x*.03,s.y*.10,s.x*.46,s.y*.49)
			g.rival = Rect2(s.x*.52,s.y*.10,s.x*.46,s.y*.49)
			if not portrait:
				g.hero = Rect2(s.x*.02,s.y*.13,s.x*.25,s.y*.66)
				g.rival = Rect2(s.x*.24,s.y*.13,s.x*.25,s.y*.66)
	return g
## Conservative head lane used to keep the reaction badge away from the face.
static func winner_head_rect(s: Vector2) -> Rect2:
	var h: Rect2 = card_geometry(s,"spotlight").hero
	return Rect2(h.position+Vector2(h.size.x*.20,0),Vector2(h.size.x*.60,h.size.y*.38))
func _warm(point: Vector2) -> bool:
	var s = region.size
	if kind != "versus": return false
	return point.y < s.y*.56-point.x*.25 if arrangement == "vertical" else point.x > s.x*.58-point.y*.25
func _build_halftone(s: Vector2):
	var verts = [PackedVector2Array(),PackedVector2Array()]
	var colors = [PackedColorArray(),PackedColorArray()]
	var step = maxf(18,minf(s.x,s.y)/24.0)
	for y in range(0,int(s.y)+1,int(step)):
		for x in range(0,int(s.x)+1,int(step)):
			var at = Vector2(x,y); var side = 1 if _warm(at) else 0
			var col = Color("d8af4e") if side == 1 else Color("4bc8e6")
			col.a = .23 if (x < s.x*.28 or x > s.x*.60) else .08
			for i in range(6):
				verts[side].append(at); verts[side].append(at+Vector2.from_angle(i*TAU/6)*step*.20); verts[side].append(at+Vector2.from_angle((i+1)*TAU/6)*step*.20)
				for j in range(3): colors[side].append(col)
	_dots_cool = P._mesh(verts[0],colors[0]) if not verts[0].is_empty() else null
	_dots_warm = P._mesh(verts[1],colors[1]) if not verts[1].is_empty() else null
func _draw_card_background():
	var s = region.size
	if kind == "versus":
		if versus_cover_rect().has_area(): draw_rect(versus_cover_rect(),Color("0b142d"))
		var cool: PackedVector2Array; var warm: PackedVector2Array
		if arrangement == "vertical":
			warm = PackedVector2Array([Vector2.ZERO,Vector2(s.x,0),Vector2(s.x,s.y*.56-s.x*.25),Vector2(0,s.y*.56)])
			cool = PackedVector2Array([Vector2(0,s.y*.56),Vector2(s.x,s.y*.56-s.x*.25),s,Vector2(0,s.y)])
		else:
			warm = PackedVector2Array([Vector2(s.x*.58,0),Vector2(s.x,0),s,Vector2(s.x*.58-s.y*.25,s.y)])
			cool = PackedVector2Array([Vector2.ZERO,Vector2(s.x*.58,0),Vector2(s.x*.58-s.y*.25,s.y),Vector2(0,s.y)])
		var pulse = 1.0 if reduced_motion else .92+.08*sin(age*2.2)
		for side in range(2):
			var offset = Motion.wipe_offset(s,age,side == 1,reduced_motion)
			draw_set_transform(offset)
			draw_colored_polygon(warm if side == 1 else cool,Color("49320d") if side == 1 else Color("0b142d"))
			var dots = _dots_warm if side == 1 else _dots_cool
			if dots: draw_mesh(dots,null,Transform2D.IDENTITY,Color(1,1,1,pulse))
			if side == 1: draw_line(warm[3],warm[0] if arrangement == "horizontal" else warm[2],Color("fff2ce"),5,true)
		draw_set_transform(Vector2.ZERO)
	else:
		draw_rect(region,Color("14305a"))
		if _dots_cool: draw_mesh(_dots_cool,null,Transform2D.IDENTITY,Color(1,1,1,1.0 if reduced_motion else .90+.10*sin(age*1.7)))
		if kind == "spotlight":
			var at = loser.position+loser.size*.5
			var radius = loser.size.x*.5
			var tint = Color(P.mark_color(3-player),loser.modulate.a)
			draw_circle(at,radius+4,Color(Color("050c1a"),loser.modulate.a))
			draw_circle(at,radius,Color(Color("132239"),loser.modulate.a))
			draw_arc(at,radius,0,TAU,64,tint,4,true)
			draw_arc(at,radius-5,0,TAU,64,Color(tint,.45*loser.modulate.a),1.5,true)
	var origin = s*.5 if kind == "versus" else s*Vector2(.50,.43)
	var reveal = Motion.out_cubic(age/.28) if not reduced_motion else 1.0
	var fade = (1.0-clampf((age-2.65)/.35,0,1)) if kind == "versus" else 1.0
	for i in range(44):
		var angle = i*TAU/44+.12+(0.0 if reduced_motion else age*.035)
		var v = Vector2.from_angle(angle)
		var drift = 0.0 if reduced_motion else fmod(age*.075+Motion.unit(i),.32)
		var a = origin+v*s.length()*(.09+drift)
		var b = (origin+v*s.length()).clamp(Vector2.ZERO,s)
		var n = v.orthogonal()*float(1+i%3)
		draw_colored_polygon(PackedVector2Array([a,b+n,b-n]),Color(1,.94,.79,(.07 if i%3 else .17)*reveal*fade))
	if kind == "versus":
		_draw_speed_lines(reveal*fade)
		_draw_trails()
	else:
		var burst = starburst(origin,Vector2(s.x*.49,s.y*.34),22,0.0 if reduced_motion else age*.045)
		draw_colored_polygon(burst,Color(.8,.88,1,.10))
		draw_polyline(burst+PackedVector2Array([burst[0]]),Color(1,.89,.67,.38),2,true)
func _draw_speed_lines(alpha: float):
	if reduced_motion: return
	var s = region.size
	for i in range(24):
		var rival = i%2 == 1
		var v = -Motion.travel(s,rival).normalized()
		var speed = 1.8 if age < .45 else .09
		var at = Vector2(fposmod(Motion.unit(i,8)+age*speed,1)*s.x,Motion.unit(i,9)*s.y)
		var length = minf(s.x,s.y)*(.12+Motion.unit(i,10)*.3)
		var col = Color(P.mark_color(3-player if rival else player),alpha*(.38 if age < .45 else .10))
		draw_line(at-v*length,at,col,1+i%2,true)
func _draw_trails():
	var exiting = age >= Motion.EXIT_AT and age < Motion.VERSUS_SECONDS
	if reduced_motion or not exiting and (age >= .48 or age <= .02): return
	for i in range(3,0,-1):
		var t = maxf(0,age-i*.033)
		var alpha = (.30-i*.05)*(1.0-clampf((age-2.9)/.1,0,1) if exiting else 1.0-clampf((age-.30)/.18,0,1))
		for rival in [false,true]:
			var art = loser if rival else hero
			if art.texture == null: continue
			var r = loser_rect if rival else hero_rect
			var offset = Motion.actor_offset(region.size,t,rival,false)
			var rect = art.texture_rect()
			var xf = Transform2D(0,r.position+offset)*art.mirror_transform()
			draw_set_transform_matrix(xf)
			draw_texture_rect(art.texture,rect,false,Color(P.mark_color(3-player if rival else player),alpha))
			draw_set_transform_matrix(Transform2D.IDENTITY)

static func starburst(at: Vector2, radius: Vector2, spikes: int = 9, rotation_angle: float = 0.0) -> PackedVector2Array:
	var points = PackedVector2Array()
	for i in range(spikes*2):
		var a = -PI*.5+i*PI/spikes+rotation_angle
		points.append(at+Vector2(cos(a),sin(a))*radius*(1.0 if i%2 == 0 else .61))
	return points
## Bundled Rajdhani, heavy keyline and 0.23 shear: no external font dependencies.
static func headline(node: CanvasItem, value: String, r: Rect2, color: Color, desired: int):
	var font = P.SANS
	# These are uppercase display cards: fit the visible capitals, rather than
	# Rajdhani's generous line box (which made the mock-sized titles look tiny).
	var fs = P.fit_size(value,r.size.x,int(desired*1.4),font)
	while fs > 9 and fs*.65 > r.size.y: fs -= 1
	var width = font.get_string_size(value,HORIZONTAL_ALIGNMENT_LEFT,-1,fs).x
	var cap_height = fs*.65
	var baseline = r.position+Vector2((r.size.x-width)*.5,(r.size.y+cap_height)*.5)
	node.draw_set_transform_matrix(Transform2D(Vector2(1,0),Vector2(-.23,1),Vector2(baseline.y*.23,0)))
	node.draw_string_outline(font,baseline,value,HORIZONTAL_ALIGNMENT_LEFT,-1,fs,maxi(3,int(fs*.10)),Color(Color("050c1a"),color.a))
	node.draw_string_outline(font,baseline,value,HORIZONTAL_ALIGNMENT_LEFT,-1,fs,maxi(1,int(fs*.015)),color)
	node.draw_string(font,baseline,value,HORIZONTAL_ALIGNMENT_LEFT,-1,fs,color)
	node.draw_set_transform_matrix(Transform2D.IDENTITY)
static func plate(node: CanvasItem, r: Rect2, screen_name: String, hero_name: String, accent: Color):
	var skew = r.size.y*.25
	var pts = PackedVector2Array([r.position+Vector2(skew,0),Vector2(r.end.x,r.position.y),r.end-Vector2(skew,0),Vector2(r.position.x,r.end.y)])
	node.draw_colored_polygon(pts,Color("091124"))
	node.draw_polyline(pts+PackedVector2Array([pts[0]]),accent,3,true)
	node.draw_line(pts[0],pts[3],accent,7,true)
	headline(node,screen_name.to_upper(),Rect2(r.position+Vector2(10,0),Vector2(r.size.x-20,r.size.y*.61)),Color.WHITE,int(r.size.y*.53))
	headline(node,hero_name.to_upper(),Rect2(r.position+Vector2(10,r.size.y*.59),Vector2(r.size.x-20,r.size.y*.35)),accent,int(r.size.y*.29))
func winner_caption() -> String:
	return "DRAW" if kind == "draw" else winner_name.to_upper()+" WINS!"
func _build_letters(g: Dictionary):
	_letters.clear()
	if kind == "versus": return
	for wins in [false,true]:
		if wins and kind == "draw": continue
		var value = "WINS!" if wins else ("DRAW" if kind == "draw" else winner_name.to_upper())
		var r: Rect2 = g.wins if wins else g.name
		var fs = P.fit_size(value,r.size.x,int(r.size.y*1.12*1.4),P.SANS)
		while fs > 9 and fs*.65 > r.size.y: fs -= 1
		# Fit the full ink envelope, including shear, keyline and 2x letter slam.
		var row = {"value":value,"positions":PackedVector2Array(),"fs":fs,"start":Motion.letter_start(winner_name.length(),wins,reduced_motion),"color":Color.WHITE if wins else Color("efc351")}
		var envelope = Rect2()
		while fs >= 9:
			row.fs = fs; row.positions = PackedVector2Array()
			for i in range(value.length()): row.positions.append(Vector2(P.SANS.get_string_size(value.substr(0,i),HORIZONTAL_ALIGNMENT_LEFT,-1,fs).x,0))
			envelope = _letter_ink_rect(row,0,2)
			for i in range(value.length()):
				for sc in [1.0,2.0]: envelope = envelope.merge(_letter_ink_rect(row,i,sc))
			if envelope.size.x <= minf(r.size.x,region.size.x-36): break
			fs -= 1
		var offset = Vector2(r.get_center().x-envelope.get_center().x,r.position.y+(r.size.y+fs*.65)*.5)
		for i in range(row.positions.size()): row.positions[i] += offset
		_letters.append(row)
func _letter_transform(row: Dictionary, i: int, sc: float) -> Transform2D:
	var p: Vector2 = row.positions[i]
	var center = p+Vector2(row.fs*.20,-row.fs*.32)
	return Transform2D(Vector2(1,0),Vector2(-.23,1),Vector2(p.y*.23,0))*Transform2D(0,Vector2.ONE*sc,0,center)
func _letter_ink_rect(row: Dictionary, i: int, sc: float) -> Rect2:
	var w = P.SANS.get_string_size(row.value[i],HORIZONTAL_ALIGNMENT_LEFT,-1,row.fs).x
	var ink = Rect2(-row.fs*.20,-row.fs*.40,w,row.fs*.76).grow(maxf(3,row.fs*.10)+2)
	return _letter_transform(row,i,sc)*ink
func headline_ink_rects(at: float = -1) -> Array:
	var out: Array = []; var t = age if at < 0 else at
	for row in _letters:
		var start = Motion.letter_start(winner_name.length(),row.value == "WINS!",reduced_motion)
		for i in range(row.value.length()):
			if t < start+(0.0 if reduced_motion else i*Motion.LETTER_STEP): continue
			out.append(_letter_ink_rect(row,i,Motion.letter_scale(t,i,start,reduced_motion)))
	return out
func _draw_letters():
	for row in _letters:
		for i in range(row.value.length()):
			var start = Motion.letter_start(winner_name.length(),row.value == "WINS!",reduced_motion)
			if age < start+(0.0 if reduced_motion else i*Motion.LETTER_STEP): continue
			var sc = Motion.letter_scale(age,i,start,reduced_motion)
			var p: Vector2 = row.positions[i]
			var center = p+Vector2(row.fs*.20,-row.fs*.32)
			front.draw_set_transform_matrix(_letter_transform(row,i,sc))
			front.draw_string_outline(P.SANS,p-center,row.value[i],HORIZONTAL_ALIGNMENT_LEFT,-1,row.fs,maxi(3,int(row.fs*.10)),Color("050c1a"))
			front.draw_string(P.SANS,p-center,row.value[i],HORIZONTAL_ALIGNMENT_LEFT,-1,row.fs,row.color)
	front.draw_set_transform_matrix(Transform2D.IDENTITY)
func particle_limit() -> int:
	if reduced_motion or kind == "draw": return 0
	return 88 if kind == "versus" else Motion.WINNER_PARTICLES
func particle_pose(i: int, at: float = -1) -> Dictionary:
	if reduced_motion or kind == "draw": return {}
	var t = age if at < 0 else at
	if kind == "versus": return Motion.particle(i,t,region.size,true,player) if t < Motion.EXIT_AT else {}
	if i >= 108:
		var second = Motion.letter_start(winner_name.length(),true,false)+4*Motion.LETTER_STEP+.27
		t -= second-Motion.CLASH
	return Motion.particle(i,t,region.size,false,player)
func live_particle_count(at: float = -1) -> int:
	var count = 0
	for i in range(particle_limit()):
		if not particle_pose(i,at).is_empty(): count += 1
	return count
func _draw_particles():
	for i in range(particle_limit()):
		var p = particle_pose(i)
		if p.is_empty(): continue
		var col = Color(P.mark_color(2 if p.gold else 1),p.alpha*.9)
		if kind != "versus": col = Color(Color.WHITE if p.confetti and i%4 == 0 else winner_accent(),p.alpha*.96)
		if not p.confetti: P.shard(front,p.position,p.length if kind == "versus" else p.length*.5,p.angle,col)
		else:
			var v = Vector2.from_angle(p.angle)*p.length*.5
			front.draw_line(p.position-v,p.position+v,col,maxf(1,p.length*.42),true)
func _draw_front():
	if combined_result and visible:
		_draw_combined(); return
	if not visible or not kind in ["versus","spotlight","draw"]: return
	var s = region.size; var g = card_geometry(s,kind)
	_draw_particles()
	if kind == "versus":
		for rival in [false,true]:
			var start = .53 if rival else .45
			if age < start and not reduced_motion: continue
			var progress = 1.0 if reduced_motion else Motion.back((age-start)/.22,.7)
			var base: Rect2 = g.rival_plate if rival else g.player_plate
			var r = Rect2(base.position+Vector2((1-progress)*s.x*(-1 if rival else 1),(1-progress)*-s.y*.07),base.size)
			var accent = P.mark_color(3-player if rival else player)
			plate(front,r,loser_name if rival else winner_name,R.get_hero(loser_id if rival else winner_id).name,accent)
			var glint = (age-start-.20)/.28
			if not reduced_motion and glint >= 0 and glint <= 1:
				var x = lerpf(r.position.x+12,r.end.x-12,glint)
				front.draw_line(Vector2(x+6,r.position.y+4),Vector2(x-6,r.end.y-4),Color(1,1,1,sin(glint*PI)*.8),4,true)
		var sc = Motion.vs_scale(age,reduced_motion)
		if sc.x > 0:
			var radius = minf(s.x,s.y)*.16
			var at = s*.5
			var burst = starburst(at,Vector2.ONE*radius*sc)
			front.draw_colored_polygon(burst,Color("fffbea")); front.draw_polyline(burst+PackedVector2Array([burst[0]]),Color("080c19"),3,true)
			headline(front,"VS",Rect2(at-Vector2(radius*.8,radius*.65)*sc,Vector2(radius*1.6,radius*1.3)*sc),Color("efc351"),int(radius*1.5*sc.y))
		var flash = Motion.flash(age,reduced_motion)
		if flash != 0:
			front.draw_rect(region,Color.WHITE if flash > 0 else Color("050914"))
			var at = s*.5
			for i in range(18):
				var v = Vector2.from_angle(i*TAU/18+.2)
				front.draw_line(at+v*30,at+v*s.length(),Color("050914") if flash > 0 else Color.WHITE,3+i%4,true)
	else:
		if kind == "spotlight" and loser.modulate.a > 0:
			var center = loser.position+loser.size*.5
			front.draw_arc(center,loser.size.x*.5,0,TAU,64,Color(P.mark_color(3-player),loser.modulate.a),4,true)
			var at = loser.position+Vector2(loser.size.x*.91,loser.size.y*.14)
			var tint = Color(P.mark_color(3-player),loser.modulate.a)
			if reduced_motion or age >= .58:
				front.draw_circle(at,8*loser.size.x/88.0,Color("0b142d"))
				for v in [Vector2(1,1),Vector2(-1,1)]: front.draw_line(at-v*4*loser.size.x/88.0,at+v*4*loser.size.x/88.0,tint,2,true)
		_draw_letters()
		var reveal = .12 if reduced_motion else Motion.letter_start(winner_name.length(),true,false)+.48
		var fade = clampf((age-reveal)/.24,0,1)
		if reduced_motion: fade = clampf((age-.12)/.12,0,1)
		if fade > 0:
			var offset = Vector2.ZERO if reduced_motion else Vector2(0,(1-Motion.out_cubic(fade))*12)
			headline(front,"A PERFECT STANDOFF" if kind == "draw" else R.get_hero(winner_id).name.to_upper(),Rect2(g.subtitle.position+offset,g.subtitle.size),Color(winner_accent(),fade),int(g.subtitle.size.y*.92))
			var fs = score_font_size()
			P.text(front,result_score,Rect2(g.subtitle.position+Vector2(0,g.subtitle.size.y+2)+offset,Vector2(g.subtitle.size.x,fs*1.25)),fs,Color(P.PALE,fade))

## The same left-video / right-result layout, including on phones.
static func combined_geometry(s: Vector2) -> Dictionary:
	var gap = 12.0 if s.x < 700 else 32.0
	var right = s.x*.50+gap*.5
	var width = s.x-right-gap
	var short = s.y < 500
	var bh = 48.0 if s.x < 700 else 54.0
	var again = Rect2(right,s.y-64-bh*2-12,width,bh)
	var menu = Rect2(right,s.y-64-bh,width,bh)
	if short:
		again = Rect2(right,s.y-68,(width-10)*.5,48)
		menu = Rect2(right+(width+10)*.5,s.y-68,(width-10)*.5,48)
	# Allocate non-overlapping text lanes before the action buttons. Previous
	# fixed offsets put the player name inside the hero outcome's first line.
	var top = 46.0 if short else s.y*.19
	var available = maxf(100,again.position.y-top-16)
	var spacing = clampf(available*.035,5,16)
	var usable = available-spacing*4
	var title_h = usable*.24
	var names_h = usable*.16
	var outcome_h = usable*.32
	var score_h = usable*.12
	var y = top
	var g = {"hero":Rect2(gap,64,s.x*.50-gap*1.5,s.y-128),"rival":Rect2(),"again":again,"menu":menu}
	g.name = Rect2(right,y,width,title_h); y += title_h+spacing
	g.names = Rect2(right,y,width,names_h); y += names_h+spacing
	g.outcome = Rect2(right,y,width,outcome_h); y += outcome_h+spacing
	g.score = Rect2(right,y,width,score_h); y += score_h+spacing
	g.detail = Rect2(right,y,width,maxf(0,again.position.y-y-12))
	return g
func result_geometry(s: Vector2) -> Dictionary:
	return combined_geometry(s) if combined_result else card_geometry(s,kind)
static func wrapped_lines(value: String, width: float, fs: int) -> Array:
	var lines: Array = []; var line = ""
	for word in value.split(" "):
		var candidate = word if line.is_empty() else line+" "+word
		if not line.is_empty() and P.text_width(candidate,fs) > width-6:
			lines.append(line); line = word
		else: line = candidate
	if not line.is_empty(): lines.append(line)
	return lines
func _wrapped(value: String, rect: Rect2, fs: int, color: Color):
	if value.is_empty() or rect.size.y < 1: return
	var lines = wrapped_lines(value,rect.size.x,fs)
	while fs > 9 and lines.size()*(P.SANS.get_height(fs)+2) > rect.size.y:
		fs -= 1
		lines = wrapped_lines(value,rect.size.x,fs)
	var line_h = minf(P.SANS.get_height(fs)+2,rect.size.y/maxi(1,lines.size()))
	for i in range(lines.size()):
		P.text(front,lines[i],Rect2(rect.position+Vector2(0,i*line_h),Vector2(rect.size.x,line_h)),fs,color,P.SANS,HORIZONTAL_ALIGNMENT_LEFT)
## Break genuinely oversized tokens instead of shrinking the entire line to dust.
static func result_wrapped_lines(value: String, width: float, fs: int) -> Array:
	var tokens: Array[String] = []
	for word in value.split(" ",false):
		if P.text_width(word,fs) <= width:
			tokens.append(word); continue
		var chunk := ""
		for glyph in word:
			if not chunk.is_empty() and P.text_width(chunk+glyph,fs) > width:
				tokens.append(chunk); chunk = ""
			chunk += glyph
		if not chunk.is_empty(): tokens.append(chunk)
	var lines: Array[String] = []
	var line := ""
	for token in tokens:
		var candidate := token if line.is_empty() else line+" "+token
		if not line.is_empty() and P.text_width(candidate,fs) > width:
			lines.append(line); line = token
		else: line = candidate
	if not line.is_empty(): lines.append(line)
	return lines
## Text has its own padded right-hand column. Hero art and action rects are unchanged.
func result_text_layout(s: Vector2, seam: Rect2 = Rect2()) -> Array:
	var g = combined_geometry(s)
	var width: float = g.name.size.x
	var inset := clampf(width*.04,7.0,25.0)
	var left: float = g.name.position.x+inset
	if seam.has_area() and left < seam.end.x and seam.end.x < g.name.end.x: left = seam.end.x+inset
	width = maxf(14,g.name.end.x-inset-left)
	var short := s.y < 500
	var top := maxf(48,minf(s.y*.1,105))
	var bottom: float = g.again.position.y-13.0
	var available := maxf(1.0,bottom-top)
	var gap := clampf(available*.037,8.0,21.0)
	var name_text := winner_name.strip_edges()
	var winner: String = R.get_hero(winner_id).name if R.valid(winner_id) else ""
	var defeated: String = R.get_hero(loser_id).name if R.valid(loser_id) else ""
	var outcome := ""
	if not winner.is_empty() and not defeated.is_empty(): outcome = winner+" defeats "+defeated
	elif not winner.is_empty() and name_text.is_empty(): outcome = winner+" wins"
	var values := [result_title,name_text,outcome,result_score,result_detail]
	var kinds := ["heading","player","matchup","score","detail"]
	var fonts := [
		maxi(24,mini(80,roundi(width*.27))),
		clampi(roundi(width*.093),14,33),
		clampi(roundi(width*.079),12,27),
		clampi(roundi(width*.061),11,22),
		14 if short else 17
	]
	var colors := [P.GOLD,P.WHITE,P.PALE,P.MUTED,P.PALE]
	var sections: Array = []
	for attempt in range(42):
		sections.clear()
		var y := 0.0
		for i in range(values.size()):
			var value: String = values[i].strip_edges()
			if value.is_empty(): continue
			var font: Font = P.DISPLAY if i == 0 else P.SANS
			var fs: int = fonts[i]
			if i == 0: fs = mini(fs,P.fit_size(value,width-10,fs,font))
			var lines: Array = [value] if i == 0 else result_wrapped_lines(value,width-9,fs)
			var border := maxi(2,roundi(fs*.085))
			var line_h := font.get_height(fs)+border*2+3
			var rect := Rect2(left,y,width,lines.size()*line_h)
			sections.append({"lines":lines,"font":font,"kind":kinds[i],"font_size":fs,"border":border,"line_height":line_h,"rect":rect,"color":colors[i]})
			y = rect.end.y+gap
		var content_height := maxf(0.0,y-gap)
		if content_height <= available or attempt == 41:
			var offset := top+maxf(0.0,(available-content_height)*.29)
			for row in sections: row.rect.position.y += offset
			return sections
		for i in range(fonts.size()): fonts[i] = maxi(10,fonts[i]-1)
		gap = maxf(6,gap-.45)
	return sections
func _current_result_rows() -> Array:
	var seam: Rect2 = _layout.get("hinge",Rect2())
	var key := [region.size,seam,result_title,winner_name,winner_id,loser_id,result_score,result_detail]
	if key != _result_copy_key:
		_result_copy_key = key
		_result_copy_rows = result_text_layout(region.size,seam)
	return _result_copy_rows
func _refresh_gold_result_title():
	if not is_instance_valid(_gold_result_title): return
	_gold_result_title.visible = combined_result and visible and result_title == "VICTORY"
	if not _gold_result_title.visible: return
	for row in _current_result_rows():
		if row.kind == "heading":
			_gold_result_title.place(row.rect,result_title,row.font,row.font_size,reduced_motion)
			break
func _draw_combined():
	var s = region.size; var g = combined_geometry(s)
	P.text(front,"LEXERLY / MATCH RESULT",Rect2(16,16,s.x-32,30),16,P.GOLD)
	P.outline(front,g.hero.grow(2),Color(P.GOLD,.55),1)
	for section in _current_result_rows():
		if section.kind == "heading" and result_title == "VICTORY": continue
		var fs: int = section.font_size
		var font: Font = section.font
		for i in range(section.lines.size()):
			var line: String = section.lines[i]
			var x: float = section.rect.get_center().x-font.get_string_size(line,HORIZONTAL_ALIGNMENT_LEFT,-1,fs).x*.5
			var baseline := Vector2(x,section.rect.position.y+section.border+font.get_ascent(fs)+i*section.line_height)
			front.draw_string_outline(font,baseline+Vector2(0,1),line,HORIZONTAL_ALIGNMENT_LEFT,-1,fs,section.border,Color(0,0,0,.75))
			front.draw_string(font,baseline,line,HORIZONTAL_ALIGNMENT_LEFT,-1,fs,section.color)
