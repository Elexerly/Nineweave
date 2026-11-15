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
func _ready():
	mouse_filter = Control.MOUSE_FILTER_IGNORE; z_index = 30; visible = false
	hero = Rig.new(); add_child(hero)
	loser = Rig.new(); loser.bust = true; add_child(loser)
func duration() -> float:
	if reduced_motion: return {"lock_in":.35,"pop":.55,"spotlight":1.0}.get(kind,.5)
	return {"lock_in":.95,"pop":1.2,"spotlight":3.0}.get(kind,1.0)
func show_scene(scene_kind: String, winner: String, rival: String, mark: int, layout: Dictionary, claimed_board: int = 4):
	kind = scene_kind; winner_id = winner; loser_id = rival; player = mark; _layout = layout
	age = 0; active = true; visible = true; frozen = false
	var s: Vector2 = layout.size; var seam: Rect2 = layout.hinge
	var safe = Rect2(Vector2(14,14),s-Vector2(28,28))
	if seam.size.x > 0: safe = Rect2(seam.end.x+12,14,s.x-seam.end.x-26,s.y-28)
	region = safe
	if kind == "pop":
		var b: Rect2 = layout.board
		var w = minf(b.size.x*.9,350); var h = minf(164,b.size.y*.38)
		var x = b.position.x+8 if claimed_board%3 == 0 else b.end.x-w-8
		region = Rect2(x,clampf(b.position.y+(claimed_board/3)*b.size.y/3,b.position.y+16,b.end.y-h-8),w,h)
		if layout.mode == "duo_landscape": region = Rect2(layout.turn.position.x,layout.stats.end.y+8,layout.turn.size.x,minf(218,layout.controls.position.y-layout.stats.end.y-20))
		hero_rect = Rect2(region.position+Vector2(2,-10),Vector2(region.size.x*.45,region.size.y+10))
	else:
		var portrait = safe.size.x < safe.size.y*.9
		hero_rect = Rect2(safe.position+Vector2(0,44),Vector2(safe.size.x*(.9 if portrait else .6),safe.size.y*(.65 if portrait else .78)))
		if portrait: hero_rect.position.x = safe.get_center().x-hero_rect.size.x*.5
	loser_rect = Rect2(region.end.x-region.size.x*.29,region.position.y+region.size.y*.38,region.size.x*.26,region.size.y*.29)
	hero.configure(winner_id); hero.side = player; hero.position = hero_rect.position; hero.size = hero_rect.size; hero.reduced_motion = reduced_motion
	hero.set_clip({"lock_in":"lock_in","pop":"board_pop","spotlight":"victory"}.get(kind,"idle"))
	loser.configure(loser_id,true); loser.side = 3-player; loser.position = loser_rect.position; loser.size = loser_rect.size; loser.reduced_motion = reduced_motion; loser.set_clip("defeat")
	loser.visible = kind == "spotlight"
	clip_word = R.get_hero(winner_id).action
	pose()
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
	var move = Vector2.ZERO if reduced_motion else Vector2((1-ease)*-region.size.x*.22,sin(ease*PI)*-6)
	hero.position = hero_rect.position+move
	hero.pivot_offset = hero.size*.5
	hero.scale = Vector2.ONE*(1 if reduced_motion else 1+sin(ease*PI)*.07)
	queue_redraw()
func _draw():
	if not active: return
	var s: Vector2 = _layout.size; var col = P.mark_color(player); var r = region
	if kind != "pop": draw_rect(Rect2(Vector2.ZERO,s),Color(.006,.018,.045,.95))
	var e = 1-pow(1-clampf(age/.24,0,1),3)
	var panel = P.polygon(r,18)
	panel[0].x += 16; panel[3].x -= 9
	draw_colored_polygon(panel,Color("0b1b34"))
	draw_polyline(panel+PackedVector2Array([panel[0]]),P.GOLD_DARK,8,true)
	draw_polyline(panel+PackedVector2Array([panel[0]]),P.GOLD,3,true)
	var origin = hero_rect.get_center()
	P.halo(self,origin,hero_rect.size.y*.8,Color(col,.24))
	var rays = 6 if reduced_motion else 22
	for i in range(rays):
		var angle = i*TAU/rays+.15
		var a = origin+Vector2.from_angle(angle)*40
		var b = origin+Vector2.from_angle(angle)*(r.size.length()*.7)
		# Clamp speed strokes inside the safe panel. Nothing crosses a fold.
		a = a.clamp(r.position+Vector2(8,8),r.end-Vector2(8,8)); b = b.clamp(r.position+Vector2(8,8),r.end-Vector2(8,8))
		draw_line(a,b,Color(col,.12*e),1+i%3,true)
	for i in range(18):
		var x = r.position.x+8+(i%3)*5; var y = r.position.y+12+(i/3)*9
		draw_circle(Vector2(x,y),1.4,Color(P.GOLD,.26))
	var h = R.get_hero(winner_id)
	if kind == "pop":
		var tr = Rect2(r.position+Vector2(r.size.x*.43,12),Vector2(r.size.x*.55,r.size.y-24))
		P.text(self,clip_word,Rect2(tr.position,Vector2(tr.size.x,tr.size.y*.42)),28,P.PALE,P.DISPLAY,HORIZONTAL_ALIGNMENT_CENTER,.5)
		P.text(self,h.pop,Rect2(tr.position+Vector2(0,tr.size.y*.43),Vector2(tr.size.x,tr.size.y*.33)),18,P.WHITE)
	else:
		P.text(self,"LEGEND LOCKED" if kind == "lock_in" else "THE WEAVE IS YOURS",Rect2(r.position+Vector2(14,10),Vector2(r.size.x-28,38)),27,P.PALE,P.SERIF)
		var portrait = r.size.x < r.size.y*.9
		var plaque = Rect2(r.position.x+16,r.end.y-r.size.y*.2,r.size.x-32,r.size.y*.15)
		if not portrait: plaque = Rect2(r.position.x+r.size.x*.54,r.end.y-r.size.y*.3,r.size.x*.42,r.size.y*.2)
		P.panel(self,plaque,false,1,true)
		P.text(self,h.name.to_upper(),Rect2(plaque.position+Vector2(6,2),Vector2(plaque.size.x-12,plaque.size.y*.48)),28,P.PALE,P.SERIF)
		var line = h.pop if kind == "lock_in" else h.victory
		# Split long lines into two rows instead of shrinking them to unreadable type.
		var words = str(line).split(" "); var half = int(ceil(words.size()*.5))
		P.text(self," ".join(words.slice(0,half)),Rect2(plaque.position+Vector2(6,plaque.size.y*.46),Vector2(plaque.size.x-12,plaque.size.y*.23)),18,P.WHITE)
		P.text(self," ".join(words.slice(half)),Rect2(plaque.position+Vector2(6,plaque.size.y*.69),Vector2(plaque.size.x-12,plaque.size.y*.23)),18,P.WHITE)
		if kind == "spotlight":
			P.outline(self,loser_rect.grow(3),P.GOLD,2)
			P.text(self,"A THREAD UNRAVELS",Rect2(loser_rect.position.x,loser_rect.end.y+4,loser_rect.size.x,22),12,P.MUTED)
		P.text(self,"TAP TO CONTINUE" if age >= .2 else "",Rect2(r.position.x+12,r.end.y-30,r.size.x-24,20),12,P.GOLD)
