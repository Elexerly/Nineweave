extends SceneTree
## Round 3c regression suite: the producer's QA code-bug list (claim pop lanes, callout
## degenerate polygons, TURNAROUND, spotlight inset, button/scorecard/plaque text fit,
## rematch rival). Engine ERROR lines fail the runner, so the callout block needs no assert.
const F = preload("res://tests/fixtures.gd")
const Main = preload("res://main/main.tscn")
const Store = preload("res://settings/store.gd")
const Profile = preload("res://characters/profile.gd")
const Layout = preload("res://ui/layout.gd")
const Cinema = preload("res://characters/cinematic.gd")
const Callout = preload("res://fx/comic_callout.gd")
const A = preload("res://fx/announcer.gd")
const P = preload("res://ui/paint.gd")
const Rig = preload("res://characters/art.gd")
const R = preload("res://characters/roster.gd")
const Select = preload("res://characters/select.gd")
const ButtonArt = preload("res://ui/ornate_button.gd")
const MainScript = preload("res://main/main.gd")
const SIZES = [[390,844],[360,640],[430,932],[375,667],[844,390],[932,430],[667,375],[568,320],[768,1024],[1024,768],[1366,1024],[1280,720],[1920,1080],[1024,720],[960,720],[800,600],[800,700],[720,700],[1180,820],[867,553],[867,500],[867,600],[669,787],[669,720],[2601,1659]]
var checks = 0
var failures = 0
func ok(value: bool, msg: String):
	checks += 1
	if not value: failures += 1; print("FAIL ",msg)
func _initialize(): run.call_deferred()
func frames(count: int = 2):
	for i in range(count): await process_frame
func blank() -> Array:
	var p: Array = []
	for i in range(9): p.append(".........")
	return p

func run():
	pop_lanes()
	announcer()
	spotlight_inset()
	select_plaque()
	await callout_fine_steps()
	var ui = Main.instantiate(); ui.test_online_bypass = true; ui.settings = Store.new("user://r3c-ui.cfg"); ui.profile = Profile.new("user://r3c-profile.cfg")
	ui.settings.values.sound = false; ui.settings.values.reduced_motion = false; ui.profile.data.onboarded = true
	root.add_child(ui); await frames()
	await live_pops(ui)
	await controls_and_scorecards(ui)
	await rematch_rival(ui)
	ui.queue_free(); await frames(3)
	print("NINEWEAVE_ROUND3C ","PASS" if failures == 0 else "FAIL"," checks=",checks," failures=",failures)
	quit(0 if failures == 0 else 1)

## Independent list of what a claim pop must leave visible (items 1-4, 11).
func protected(l: Dictionary) -> Dictionary:
	var out = {"board":l.board}
	if l.hinge.size.x > 0: out.hinge = l.hinge
	for key in ["character","hero_player","hero_opponent","players","info","minimap","controls","message","turn","stats"]:
		if l.has(key) and l[key].size.y > 0: out[key] = l[key]
	var hb = 52.0 if l.mode == "landscape" else 44.0
	out.home = Rect2(l.header.position,Vector2(hb,hb)); out.settings = Rect2(l.header.end.x-hb,l.header.position.y,hb,hb)
	return out
func layouts() -> Array:
	var out: Array = []
	for size in SIZES:
		var s = Vector2(size[0],size[1]); var l = Layout.compute(s)
		out.append([str(s),l])
		if l.mode == "duo_landscape": out.append([str(s)+" hinge",Layout.compute(s,Rect2(s.x*.5-10,0,20,s.y))])
	return out

# ------------------------------------------------------------ 1-4, 11. pop lanes
func pop_lanes():
	var banners = 0; var cards = 0
	for entry in layouts():
		var id: String = entry[0]; var l: Dictionary = entry[1]
		var view = Rect2(Vector2.ZERO,l.size)
		var keep = protected(l)
		for b in range(9):
			var pop = Cinema.pop_region(l,b)
			ok(pop.size.x >= 120 and pop.size.y >= 28,id+" pop exists for board %d %s" % [b,pop])
			ok(view.encloses(pop),id+" pop inside view %d" % b)
			for key in keep:
				ok(not pop.intersects(keep[key]),id+" board %d pop %s clear of %s %s" % [b,pop,key,keep[key]])
			if pop.size.y < Cinema.CARD_MIN.y: banners += 1
			else: cards += 1
	# Pinned producer cases.
	var duo = Layout.compute(Vector2(867,553))
	ok(not Cinema.pop_region(duo,4).intersects(duo.character),"867x553 pop leaves the Duo character panel visible")
	var ipad = Layout.compute(Vector2(1366,1024))
	ok(not Cinema.pop_region(ipad,0).intersects(ipad.info) and Cinema.pop_region(ipad,0).size.y >= Cinema.CARD_MIN.y,"1366x1024 full card off the Active Board heading")
	var phone = Layout.compute(Vector2(390,844))
	for b in range(9):
		var pop = Cinema.pop_region(phone,b)
		ok(not pop.intersects(phone.hero_player) and not pop.intersects(phone.hero_opponent),"390x844 pop between the busts, board %d" % b)
	var small = Layout.compute(Vector2(568,320))
	ok(not Cinema.pop_region(small,0).intersects(small.board) and Cinema.pop_region(small,0).size.y < Cinema.CARD_MIN.y,"568x320 compact banner off the board")
	ok(cards > 0 and banners > 0,"both card and banner variants in use (cards=%d banners=%d)" % [cards,banners])

func live_pops(ui):
	# Real scene: the pop vs the live hero nodes and control buttons at all 25 sizes.
	for size in SIZES:
		var s = Vector2(size[0],size[1]); ui.set_view_size(s); await frames(1)
		ui.start_game("local"); ui._debug_capture = false
		var p = blank(); p[0] = "XX.OO...."
		ui.debug_load_position(F.position(p,1,0).serialize(),"local"); ui._debug_capture = false
		ui._input_beat = 0; ui.play_cell(0,2)
		var c = ui.cinematic
		ok(c.active and c.kind == "pop","%s claim pops" % s)
		var region: Rect2 = c.region
		for key in ui.field_heroes:
			var rig = ui.field_heroes[key]
			ok(not region.intersects(Rect2(rig.position,rig.size)),"%s pop clear of live hero %s" % [s,key])
		for id in ["home","settings","undo","hint"]:
			if ui.controls.has(id): ok(not region.intersects(Rect2(ui.controls[id].position,ui.controls[id].size)),"%s pop clear of button %s" % [s,id])
		ok(c.hero.bust and Rect2(region.position,region.size).encloses(Rect2(c.hero_rect.position,c.hero_rect.size)),"%s illustrated reaction head inside its panel" % s)
		ok(c.mouse_filter == Control.MOUSE_FILTER_IGNORE and c.hero.mouse_filter == Control.MOUSE_FILTER_IGNORE,"%s pop non-modal" % s)
		# The board keeps taking moves while the pop plays.
		var target = ui.game.active_board
		var moved = false
		for cell in range(9):
			if target >= 0 and ui.game.is_legal(target,cell):
				ui._input_beat = 0; moved = ui.play_cell(target,cell); break
		ok(moved or target < 0,"%s board accepts input under a pop" % s)
	# Reduced motion keeps the short, still pop; skipping still works.
	ui.set_view_size(Vector2(360,640)); ui.settings.values.reduced_motion = true; ui._apply_preferences()
	ui.start_game("local"); var q = blank(); q[0] = "XX.OO...."
	ui.debug_load_position(F.position(q,1,0).serialize(),"local"); ui._debug_capture = false; ui._input_beat = 0; ui.play_cell(0,2)
	ok(ui.cinematic.active and ui.cinematic.banner and is_equal_approx(ui.cinematic.duration(),.55),"360x640 reduced-motion banner pop")
	ui.cinematic.advance(.05); ok(ui.cinematic.hero.position == ui.cinematic.hero_rect.position,"reduced motion: no slide")
	ui.cinematic.advance(.2); ok(ui.cinematic.skip() and not ui.cinematic.active,"banner pop skippable")
	ui.settings.values.reduced_motion = false; ui._apply_preferences()
	# Relayout (round 3b #7) still re-places, and can switch card <-> banner.
	ui.set_view_size(Vector2(1366,1024)); ui.start_game("local")
	ui.debug_load_position(F.position(q,1,0).serialize(),"local"); ui._debug_capture = false; ui._input_beat = 0; ui.play_cell(0,2)
	ok(not ui.cinematic.banner and ui.cinematic.hero.bust,"1366x1024 card pop uses illustrated reaction head")
	ui.set_view_size(Vector2(568,320))
	ok(ui.cinematic.active and ui.cinematic.banner and ui.cinematic.hero.bust and ui.cinematic.region == Cinema.pop_region(ui.layout,0),"resize to 568x320 re-places as a banner")
	ui.go_home()

# ------------------------------------------------------------ 5. callout ERROR
func callout_fine_steps():
	# Each step is drawn; the runner fails on any engine ERROR line (degenerate polygon).
	var c = Callout.new(); c.size = Vector2(420,300); root.add_child(c); c.set_process(false)
	c.region = Rect2(20,20,380,52)
	for id in ["clean_sweep","nineweave","shutout","ready"]:
		c.show_callout(id)
		while c.age < 1.0:
			c.age += 1.0/240; c.queue_redraw(); await process_frame
	# Dense sweep of the final 2% where the sparks shrink to zero.
	c.show_callout("clean_sweep")
	for i in range(200):
		c.age = .95*(.98+i*.0001); c.queue_redraw(); await process_frame
	ok(not P.DIAMOND_MIN > .5,"diamond guard threshold")
	var probe = Probe.new(); probe.size = Vector2(420,300); root.add_child(probe); await frames(2)
	ok(probe.drawn,"tiny diamonds skipped without engine error")
	probe.queue_free(); c.queue_free(); await frames(1)
class Probe extends Control:
	var drawn = false
	func _draw():
		# Same transform and spark positions as the callout's last frames.
		draw_set_transform(Vector2(210,46),-.035,Vector2.ONE)
		for i in range(14):
			var pos = Vector2.from_angle(i*2.39996)*Vector2(190,36.4)*1.6
			for k in range(60): P.diamond(self,pos,k*.0085,Color.WHITE)
		for r in [0.0,-3.0,NAN]: P.diamond(self,Vector2(20,20),r,Color.WHITE)
		draw_set_transform(Vector2.ZERO,0,Vector2.ONE)
		drawn = true

# ------------------------------------------------------------ 6. TURNAROUND
func pos(owners: Array, turn: int = 1) -> Dictionary: return {"owners":owners,"status":0,"turn":turn,"moves":10}
func announcer():
	var e = A.events(pos([2,0,0,0,0,0,0,0,0]),pos([2,0,1,0,0,0,0,0,0],2))
	ok("turnaround" in e,"behind 0-1 -> level 1-1 is TURNAROUND")
	e = A.events(pos([2,0,0,0,2,0,0,0,0]),pos([2,0,1,0,2,0,0,0,0],2))
	ok(not "turnaround" in e,"still behind after the claim is not TURNAROUND")
	e = A.events(pos([2,2,0,0,0,1,1,0,0]),pos([2,2,1,0,0,1,1,0,0],2))
	ok("shutout" in e and not "turnaround" in e,"blocking while level is SHUTOUT, not TURNAROUND")
	e = A.events(pos([2,2,0,0,1,0,0,0,0]),pos([2,2,1,0,1,0,0,0,0],2))
	ok(e[0] == "shutout" and "turnaround" in e,"block that levels: SHUTOUT leads, TURNAROUND kept")
	e = A.events(pos([1,0,0,0,2,1,0,2,0]),pos([1,0,0,0,2,1,1,2,0],2))
	ok(not "turnaround" in e and not "shutout" in e,"unrelated open rival threat no longer counts")
	e = A.events(pos([1,0,0,0,0,0,0,0,0]),pos([1,0,0,0,1,0,0,0,0],2))
	ok(not "turnaround" in e and "double_lock" in e,"leading claim is not TURNAROUND")
	e = A.events(pos([2,0,0,0,0,0,0,0,0],2),pos([2,0,0,0,0,0,0,0,2],1))
	ok(not "turnaround" in e,"leader extending is not TURNAROUND")
	ok(A.TEXT.size() == 13 and A.TEXT.turnaround == "TURNAROUND!" and A.WEIGHT.turnaround == 5,"all line ids/texts kept")
	ok(FileAccess.file_exists("res://assets/audio") or DirAccess.dir_exists_absolute("res://assets/audio"),"audio folder kept")
	# Rate over random legal games: the old rule (behind, or any open rival threat).
	var Rules = preload("res://kernel/rules.gd")
	var counts = {"turnaround":0,"first_claim":0,"old":0}
	var rng = RandomNumberGenerator.new(); rng.seed = 33
	for g in range(120):
		var game = Rules.new(); game.new_game()
		var prev = A.snapshot(game)
		while game.status == 0:
			var moves = game.legal_moves(); var m = moves[rng.randi()%moves.size()]
			game.play(m.x,m.y)
			var now = A.snapshot(game)
			var found = A.events(prev,now)
			for id in found: if counts.has(id): counts[id] += 1
			var p = int(prev.turn)
			if now.status == 0 and now.owners.count(p) > prev.owners.count(p) and (prev.owners.count(p) < prev.owners.count(3-p) or not A.threats(prev.owners,3-p).is_empty()): counts.old += 1
			if "turnaround" in found: ok(prev.owners.count(p) < prev.owners.count(3-p) and now.owners.count(p) >= now.owners.count(3-p),"TURNAROUND only from behind to level")
			prev = now
	print("TURNAROUND_RATE ",counts)
	ok(counts.turnaround*2 <= counts.old,"TURNAROUND at most half as often as the old rule "+str(counts))

# ------------------------------------------------------------ 7. spotlight inset
func spotlight_inset():
	var aspect = Cinema.LOSER_VIEW.x/Cinema.LOSER_VIEW.y
	for entry in layouts():
		var id: String = entry[0]; var l: Dictionary = entry[1]
		var s: Vector2 = l.size; var safe = Rect2(Vector2(14,14),s-Vector2(28,28))
		if l.hinge.size.x > 0: safe = Rect2(l.hinge.end.x+12,14,s.x-l.hinge.end.x-26,s.y-28)
		var frame = Cinema.loser_frame(safe); var plaque = Cinema.spotlight_plaque(safe); var cap = Cinema.loser_caption(frame)
		ok(frame.size.y >= 60 and absf(frame.size.x/frame.size.y-aspect) < .01,id+" inset has the bust aspect "+str(frame))
		ok(safe.encloses(frame.grow(3)) and frame.position.y >= safe.position.y+50,id+" inset inside the panel, below the title")
		ok(not frame.grow(3).intersects(plaque.grow(6)),id+" inset clear of the plaque")
		ok(not cap.intersects(plaque.grow(6)) and cap.position.y > frame.end.y+3,id+" caption clear of plaque frame")
	# Illustrated replacements preserve each full 256px canvas, with no per-face crops.
	for h in R.DATA:
		var rig = Rig.new(); rig.size = Vector2(157,178); root.add_child(rig); rig.configure(h.id,true); rig.set_clip("defeat")
		for face in ["neutral","pout","panic"]:
			rig.expression = face; rig.refresh_texture()
			ok(rig.clip_contents and rig.texture.get_size() == Vector2(256,256),"%s complete illustrated head canvas %s" % [h.id,face])
		rig.free()

# ------------------------------------------------------------ 10. select plaque
func select_plaque():
	for size in SIZES:
		var s = Layout.logical_size(Vector2(size[0],size[1]))
		var g = Select.geometry(s); var lanes = Select.plaque_lanes(g.plaque)
		ok(lanes.name.position.y >= g.plaque.position.y+lanes.frame-.01 and lanes.line.end.y <= g.plaque.end.y-lanes.frame+.01,"%s plaque lanes inside the frame" % s)
		for h in R.DATA:
			var name = h.name.to_upper()
			var fs = P.fit_box(name,lanes.name,25,P.SERIF)
			ok(P.SERIF.get_height(fs) <= lanes.name.size.y+2 and P.text_width(name,fs) <= lanes.name.size.x,"%s %s fits the plaque (%d px)" % [s,name,fs])
			var lfs = P.fit_box(h.pop,lanes.line,18)
			ok(P.SANS.get_height(lfs) <= lanes.line.size.y+2 and P.text_width(h.pop,lfs) <= lanes.line.size.x,"%s %s line fits" % [s,h.id])
	var phone = Select.plaque_lanes(Select.geometry(Vector2(390,844)).plaque)
	ok(P.fit_box("VESPER VALE",phone.name,25,P.SERIF) >= 14,"390x844 VESPER VALE stays readable")

# ------------------------------------------------------------ 8, 9. buttons / scorecards
func controls_and_scorecards(ui):
	ui.start_game("computer",1); ui._debug_capture = true; ui.thinking = false
	for size in SIZES:
		var s = Vector2(size[0],size[1]); ui.set_view_size(s); await frames(1)
		for id in ["undo","hint"]:
			var b = ui.controls[id]
			if b.size.y-4 >= 62: continue
			var g = ButtonArt.caption_layout(b.size,b.caption,b.font_size)
			var ink: Rect2 = g.ink; var inner: Rect2 = g.inner
			ok(inner.grow(.5).encloses(ink),"%s %s caption inside its frame %s in %s" % [s,id,ink,inner])
			ok(g.fs >= 12,"%s %s caption readable (%d px)" % [s,id,g.fs])
			var icon = Rect2(g.icon_center-Vector2.ONE*g.icon_size*.85,Vector2.ONE*g.icon_size*1.7)
			ok(not icon.intersects(ink),"%s %s icon clear of caption" % [s,id])
		if ui.layout.mode == "landscape": continue
		var r: Rect2 = ui.layout.players
		var gap = minf(46,r.size.x*.12); var width = (r.size.x-gap)/2
		for right in [false,true]:
			var card = Rect2(r.end.x-width,r.position.y,width,r.size.y) if right else Rect2(r.position,Vector2(width,r.size.y))
			var g = MainScript.scorecard_geometry(card,right)
			var medal = Rect2(g.center-Vector2.ONE*g.ring,Vector2.ONE*g.ring*2).grow(-.01)
			ok(not g.name.intersects(medal) and not g.line.intersects(medal),"%s %s label lanes clear of medallion" % [s,"rival" if right else "you"])
			for caption in ["You","Rival AI","Thinking...","Player O"]:
				var shown = MainScript.fit_label(caption,g.name.size.x,17 if card.size.y < 70 else 20)
				ok(P.text_width(shown,P.fit_size(shown,g.name.size.x,20)) <= g.name.size.x-4,"%s %s name fits" % [s,caption])
			for n in [0,1,9]:
				var c = MainScript.claimed_line(n,g.line.size.x,card.size.y)
				ok(c.width <= g.line.size.x-4 and c.fs >= 11,"%s '%s' fits beside the medallion" % [s,c.text])
	# Round 4b keeps the winner pose and adds a small, separate loser head reaction.
	for size in SIZES:
		ui.set_view_size(Vector2(size[0],size[1])); ui.debug_scenario("win_spotlight",.5)
		var c = ui.cinematic; var g = Cinema.card_geometry(ui.layout.size,"spotlight")
		ok(c.active and c.kind == "spotlight" and c.hero_rect == g.hero and c.hero.art_key == "victory" and c.loser.visible and c.loser.bust,"%s live winner card uses the winner victory pose plus a small loser head" % str(size))
		ok(Rect2(Vector2.ZERO,ui.layout.size).encloses(c.hero_rect) and not g.again.intersects(g.menu),"%s winner art inside viewport, actions apart" % str(size))
		c.clear()

	ui.start_game("computer",1); ui._debug_capture = true; ui.thinking = false
	var tight = MainScript.scorecard_geometry(Rect2(454-128,62,100.3,48),true)
	ok(tight.name.end.x <= tight.center.x-tight.radius,"568x320 Rival AI ends before the medallion")

# ------------------------------------------------------------ 12. rematch rival
func rematch_rival(ui):
	ui.set_view_size(Vector2(390,844)); seed(7)
	ui.start_game("computer",1)
	var first = ui.rival_character
	for i in range(8):
		ui.start_game("computer",1,true)
		ok(ui.rival_character == first,"Play Again keeps the same rival (%d)" % i)
	ui.overlay = "result"; ui._rebuild(); ui.controls.again.pressed.emit()
	ok(ui.rival_character == first and ui.overlay.is_empty(),"Play Again button rematches the same rival")
	var changed = false
	for i in range(12):
		ui.start_game("computer",1)
		if ui.rival_character != first: changed = true
		ok(ui.rival_character != str(ui.profile.data.character_id),"rival never the player's hero")
	ok(changed,"a new game from the menu still re-rolls")
	ui.rival_character = str(ui.profile.data.character_id); ui.start_game("computer",1,true)
	ok(ui.rival_character != str(ui.profile.data.character_id),"rematch re-picks a clashing rival")
	ui.go_home()
