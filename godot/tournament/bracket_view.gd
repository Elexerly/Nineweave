extends Control
## Reusable, presentation-only bracket. Feed a model and a batch of result events.
## No session, AI, disk, timer callbacks or network knowledge. Live consumers can
## call present() repeatedly; seek() also makes every animation frame capturable.
const B = preload("res://tournament/bracket.gd")
const P = preload("res://ui/paint.gd")
const Art = preload("res://characters/art.gd")
const R = preload("res://characters/roster.gd")
const ADVANCE_SECONDS = 1.15
const FLIP_SECONDS = .34
signal reveal_finished
var model: Dictionary = {}
var results: Array = []
var focus_id: String = ""
var current_id: String = ""
var reduced_motion: bool = false
var age: float = 0
var geo: Dictionary = {}
var _notified: bool = false
func _ready():
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(_layout)
	_layout()
func present(bracket_model: Dictionary, result_batch: Array = [], focus: String = "", current: String = ""):
	model = bracket_model.duplicate(true); results = result_batch.duplicate(true)
	focus_id = focus if not focus.is_empty() else str(model.get("focus_id","")); current_id = current
	if current_id.is_empty():
		var next = B.next_match(model,focus_id)
		if not next.is_empty(): current_id = next.match.id
	age = 0; _notified = false; _layout()
func _layout():
	geo = geometry(size,model); queue_redraw()
func _process(delta):
	age += minf(delta,.1)
	if not _notified and settled(): _notified = true; reveal_finished.emit()
	queue_redraw()
func seek(seconds: float): age = maxf(0,seconds); queue_redraw()
func start_at(index: int) -> float:
	if reduced_motion: return 0
	return 0.0 if index == 0 and results[index].winner == focus_id else .30+index*.28
func duration_at(index: int) -> float:
	return 0.0 if reduced_motion else (ADVANCE_SECONDS if results[index].winner == focus_id else FLIP_SECONDS)
func settled() -> bool:
	for i in range(results.size()):
		if age < start_at(i)+duration_at(i): return false
	return true
func _event(r: int, i: int) -> int:
	for n in range(results.size()):
		if results[n].round == r and results[n].index == i: return n
	return -1
func progress(n: int) -> float:
	if n < 0 or reduced_motion: return 1
	return clampf((age-start_at(n))/maxf(.001,duration_at(n)),0,1)
static func geometry(s: Vector2, data: Dictionary) -> Dictionary:
	var out = {"cards":[],"labels":[],"portrait":s.x < 650,"crown":Rect2()}
	if data.is_empty() or s.x <= 0 or s.y <= 0: return out
	var nr: int = data.rounds.size()
	if out.portrait:
		var scale_y = s.y/470.0
		var cw = (s.x-28)*.5; var ch = 66.0*scale_y
		for r in range(nr):
			var stage = nr-1-r; var cards: Array = []
			var y = (60 if stage == 0 else (190 if stage == 1 else 302))*scale_y
			for i in range(data.rounds[r].size()):
				var x = (s.x-cw)*.5 if stage == 0 else (0.0 if i < data.rounds[r].size()/2 else s.x-cw)
				var dy = (i%2)*92*scale_y if stage == 2 else 0.0
				cards.append(Rect2(x,y+dy,cw,ch))
			out.cards.append(cards); out.labels.append(Rect2(0,y-27*scale_y,s.x,22*scale_y))
		out.crown = Rect2(s.x*.5-15,0,30,30*scale_y)
	else:
		var gap = 64.0; var cw = minf(240,(s.x-gap*(nr-1))/nr)
		var ch = minf(88,(s.y-70)/4.6)
		var pitch = (s.x-cw)/maxi(1,nr-1)
		for r in range(nr):
			var cards: Array = []; var count: int = data.rounds[r].size()
			for i in range(count):
				var y = 44+(s.y-54)/count*(i+.5)-ch*.5
				cards.append(Rect2(r*pitch,y,cw,ch))
			out.cards.append(cards); out.labels.append(Rect2(r*pitch,4,cw,26))
		out.crown = Rect2(s.x-cw*.5-18,s.y-32,36,32)
	return out
func row_rect(r: int, i: int, side: int) -> Rect2:
	var card: Rect2 = geo.cards[r][i]
	return Rect2(card.position+Vector2(4,4+side*(card.size.y-8)*.5),Vector2(card.size.x-8,(card.size.y-8)*.5))
func connection(r: int, i: int) -> PackedVector2Array:
	if r+1 >= geo.cards.size(): return PackedVector2Array()
	var src: Rect2 = geo.cards[r][i]; var dest: Rect2 = geo.cards[r+1][int(i/2)]
	if not geo.portrait:
		var a = Vector2(src.end.x,src.get_center().y); var b = Vector2(dest.position.x,dest.get_center().y)
		var x = (a.x+b.x)*.5
		return PackedVector2Array([a,Vector2(x,a.y),Vector2(x,b.y),b])
	if model.rounds[r].size() == 4:
		var left = i < 2; var a = Vector2(src.end.x if left else src.position.x,src.get_center().y)
		var b = Vector2(dest.end.x if left else dest.position.x,dest.get_center().y)
		var x = size.x*.5+(-5 if left else 5)
		return PackedVector2Array([a,Vector2(x,a.y),Vector2(x,b.y),b])
	var a = Vector2(src.get_center().x,src.position.y); var b = Vector2(dest.get_center().x,dest.end.y)
	var y = (a.y+b.y)*.5
	return PackedVector2Array([a,Vector2(a.x,y),Vector2(b.x,y),b])
func _visible_id(r: int, i: int, side: int) -> String:
	var id: String = model.rounds[r][i]["a" if side == 0 else "b"]
	if r > 0:
		var n = _event(r-1,i*2+side)
		if n >= 0 and progress(n) < 1: return ""
	return id
func _portrait(id: String, rect: Rect2, alpha: float = 1):
	var person: Dictionary = model.entrants.get(id,{})
	var hero = str(person.get("hero_id",""))
	if R.valid(hero):
		draw_texture_rect(Art.get_texture(hero,"head_neutral"),rect,false,Color(1,1,1,alpha))
	else:
		P.diamond(self,rect.get_center(),rect.size.y*.35,Color(P.GOLD,alpha))
func _draw():
	if model.is_empty() or geo.cards.is_empty(): return
	for r in range(geo.cards.size()-1):
		for i in range(geo.cards[r].size()):
			var points = connection(r,i); draw_polyline(points,Color("304259"),1.5,true)
			var game: Dictionary = model.rounds[r][i]
			if game.resolved and game.winner == focus_id and progress(_event(r,i)) >= 1:
				draw_polyline(points,Color(P.BLUE,.9),2.5,true)
	for r in range(geo.cards.size()):
		var label = B.round_name(model,r).to_upper()
		# Rails pass behind headings on the ascending phone composition.
		# Keep the ink lane opaque so no line cuts through the round's name.
		var lane: Rect2 = geo.labels[r]
		var width = P.text_width(label,13)+16
		draw_rect(Rect2(lane.get_center().x-width*.5,lane.position.y,width,lane.size.y),Color("071222"))
		P.text(self,label,geo.labels[r],13,P.GOLD,P.SANS)
		for i in range(geo.cards[r].size()): _card(r,i)
	var final: Rect2 = geo.cards.back()[0]
	if geo.portrait:
		var label: Rect2 = geo.labels.back()
		draw_line(Vector2(final.get_center().x,final.position.y),Vector2(final.get_center().x,label.end.y),P.GOLD,1.5,true)
		draw_line(Vector2(final.get_center().x,label.position.y),Vector2(final.get_center().x,geo.crown.end.y),P.GOLD,1.5,true)
	trophy(self,geo.crown,P.GOLD)
	for n in range(results.size()): _draw_result(n)
func _card(r: int, i: int):
	var game: Dictionary = model.rounds[r][i]; var card: Rect2 = geo.cards[r][i]
	var current = game.id == current_id and settled()
	var n = _event(r,i); var p = progress(n)
	var flip = n >= 0 and results[n].winner != focus_id and p > 0 and p < 1 and not reduced_motion
	if flip:
		var sy = maxf(.06,absf(cos(p*PI))); var center = card.get_center()
		draw_set_transform(Vector2(0,center.y*(1-sy)),0,Vector2(1,sy))
	var pulse = 1.0 if reduced_motion else .65+.35*sin(age*3.2)
	if current: P.box_glow(self,card,Color(P.BLUE,.13+.12*pulse),6,4)
	draw_style_box(_frame(current),card)
	if current:
		draw_line(card.position+Vector2(12,0),Vector2(card.end.x-12,card.position.y),Color(P.BLUE,.7+.3*pulse),2,true)
	for side in range(2):
		var id = _visible_id(r,i,side); var row = row_rect(r,i,side)
		var known = not id.is_empty(); var you = id == focus_id
		var lost = known and (B.eliminated(model,id) or model.entrants.get(id,{}).get("eliminated",false)) and (n < 0 or p > .15)
		var alpha = .32 if lost else 1.0
		if you: draw_rect(row,Color(P.BLUE,.09))
		if side == 0: draw_line(Vector2(row.position.x+2,row.end.y),Vector2(row.end.x-2,row.end.y),Color("28364b"),1,true)
		var icon_size = minf(row.size.y-2,34)
		var icon = Rect2(row.position+Vector2(1,(row.size.y-icon_size)*.5),Vector2.ONE*icon_size)
		if known:
			var fall = sin(p*PI)*8 if lost and n >= 0 and p < 1 and not reduced_motion else 0.0
			_portrait(id,Rect2(icon.position+Vector2(0,fall),icon.size),alpha)
			if lost:
				var c = icon.get_center()+Vector2(0,fall)
				draw_polyline(PackedVector2Array([c+Vector2(-6,-10),c+Vector2(2,-3),c+Vector2(-2,3),c+Vector2(7,11)]),Color(P.GOLD,.55),1,true)
		var label = str(model.entrants[id].get("name",id)) if known else ("BYE" if r == 0 else "Awaiting winner")
		var scored = game.get("score") is Dictionary
		var text_rect = Rect2(row.position+Vector2(icon_size+3,0),Vector2(row.size.x-icon_size-7-(22 if you else 0)-(20 if scored else 0),row.size.y))
		P.text(self,label,text_rect,P.fit_box(label,text_rect,16 if not geo.portrait else 14),Color(P.PALE if you else P.WHITE,alpha),P.SANS,HORIZONTAL_ALIGNMENT_LEFT)
		if you: P.text(self,"YOU",Rect2(row.end.x-25-(20 if scored else 0),row.position.y,24,row.size.y),10,P.BLUE)
		if scored: P.text(self,str(int(game.score.get("a" if side == 0 else "b",0))),Rect2(row.end.x-21,row.position.y,20,row.size.y),16,P.GOLD)
	if game.get("status","") in ["live","ready"]:
		draw_circle(card.position+Vector2(card.size.x-4,3),2.5,P.BLUE if game.status == "live" else P.GOLD)
	if flip:
		draw_set_transform(Vector2.ZERO)
		P.outline(self,card,Color(P.PALE,sin(p*PI)*.6),2)
func _frame(active: bool) -> StyleBoxFlat:
	var style = StyleBoxFlat.new(); style.bg_color = Color("10273c") if active else Color("0b192b")
	style.border_color = P.BLUE if active else Color("5d5139"); style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	return style
func _draw_result(n: int):
	var e: Dictionary = results[n]; var p = progress(n)
	if reduced_motion or e.winner != focus_id or p <= 0 or p >= 1: return
	var pose = advance_pose(n)
	var points: PackedVector2Array = pose.path
	var travel: float = pose.travel
	for j in range(14,0,-1):
		var t = maxf(0,travel-j*.018)
		var at = along(points,t)
		draw_circle(at,3*(1-j/15.0),Color(P.BLUE,(1-j/15.0)*.6),true)
	var at: Vector2 = pose.position; var radius: float = pose.radius
	P.halo(self,at,radius*1.45,Color(P.BLUE,.4)); draw_circle(at,radius,Color("112c43"))
	_portrait(e.winner,Rect2(at-Vector2.ONE*radius,Vector2.ONE*radius*2))
	draw_arc(at,radius+1,0,TAU,32,P.PALE,2,true)
func advance_pose(n: int) -> Dictionary:
	# Shared by the actual renderer and geometry checks. Includes the final's
	# last flight into the crown, for future live tournaments using this view.
	var e: Dictionary = results[n]; var p = progress(n)
	var game: Dictionary = model.rounds[e.round][e.index]
	var from = row_rect(e.round,e.index,0 if game.a == e.winner else 1).get_center()
	var final: bool = e.round+1 >= geo.cards.size()
	var to: Vector2 = geo.crown.get_center() if final else row_rect(e.round+1,int(e.index/2),e.index%2).get_center()
	var points = PackedVector2Array([from])
	if not final: points.append_array(connection(e.round,e.index))
	else: points.append(Vector2(to.x,from.y))
	points.append(to)
	var travel = 1.0-pow(1.0-p,3)
	var radius = 19.0*lerpf(1,.55,travel) if final else 19.0
	return {"path":points,"travel":travel,"position":along(points,travel),"radius":radius}
static func along(points: PackedVector2Array, t: float) -> Vector2:
	var length = 0.0
	for i in range(points.size()-1): length += points[i].distance_to(points[i+1])
	var remain = length*clampf(t,0,1)
	for i in range(points.size()-1):
		var d = points[i].distance_to(points[i+1])
		if remain <= d: return points[i].lerp(points[i+1],remain/maxf(.001,d))
		remain -= d
	return points[-1]
static func trophy(node: CanvasItem, r: Rect2, col: Color):
	var at = r.get_center(); var s = minf(r.size.x,r.size.y)/2
	node.draw_arc(at+Vector2(-s*.57,-s*.26),s*.33,PI*.35,PI*1.8,16,col,maxf(1,s*.12),true)
	node.draw_arc(at+Vector2(s*.57,-s*.26),s*.33,-PI*.8,PI*.65,16,col,maxf(1,s*.12),true)
	node.draw_colored_polygon(PackedVector2Array([at+Vector2(-s*.66,-s*.8),at+Vector2(s*.66,-s*.8),at+Vector2(s*.47,-s*.02),at+Vector2(0,s*.3),at+Vector2(-s*.47,-s*.02)]),col)
	node.draw_line(at+Vector2(-s*.4,-s*.63),at+Vector2(s*.35,-s*.63),col.lightened(.55),maxf(1,s*.07),true)
	node.draw_line(at+Vector2(0,s*.2),at+Vector2(0,s*.67),col,maxf(1,s*.15),true)
	node.draw_rect(Rect2(at+Vector2(-s*.5,s*.66),Vector2(s,s*.2)),col)
